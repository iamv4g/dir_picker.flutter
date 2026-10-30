import 'dart:convert';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../location/file_system_entry.dart';
import '../../location/picked_location.dart';
import '../../options/pick_options.dart';
import '../../platform_interface/dir_picker_platform.dart';
import '../io_entries.dart';
import '../io_tokens.dart';
import 'app_window.dart';

/// Thrown when a picker method is not available on the current system
/// (e.g. portal daemon not running, CLI tool not installed).
/// Distinct from user cancellation, which returns null.
class _PickerUnavailableException implements Exception {}

/// DirPicker implementation for Linux.
///
/// Uses the following methods in order of priority:
/// 1. XDG Desktop Portal (`org.freedesktop.portal.FileChooser`) via D-Bus —
///    works on all desktop environments including sandboxed apps (Flatpak/Snap).
/// 2. `zenity` CLI (GNOME/GTK desktops) — fallback if portal is unavailable.
/// 3. `kdialog` CLI (KDE desktops) — final fallback.
///
/// Each method throws [_PickerUnavailableException] if the tool is not present,
/// allowing the next fallback to be tried. A null return always means the user
/// cancelled — the fallback chain stops immediately. zenity or kdialog
/// failing with an exit code other than 1 throws `Exception('PICKER_ERROR: …')`. If no method is available,
/// [pick] throws an [UnsupportedError].
class DirPickerLinux extends DirPickerPlatform {
  DirPickerLinux() : this.withBackends();

  /// Creates an instance with replaceable picker backends.
  ///
  /// [portalPicker] replaces the XDG Desktop Portal call. Throwing from it
  /// marks the portal as unavailable. [sessionBus] replaces
  /// [DBusClient.session] for the real portal call. [runProcess] replaces
  /// [Process.run] for the zenity and kdialog fallbacks. [appWindow]
  /// replaces the lookup of the app window's X11 ID.
  @visibleForTesting
  DirPickerLinux.withBackends({
    this._portalPicker,
    DBusClient Function()? sessionBus,
    Future<ProcessResult> Function(String executable, List<String> arguments)?
    runProcess,
    int? Function()? appWindow,
  }) : _sessionBus = sessionBus ?? DBusClient.session,
       _runProcess = runProcess ?? Process.run,
       _appWindow = appWindow ?? appWindowXid;

  static void registerWith() {
    DirPickerPlatform.instance = DirPickerLinux();
  }

  final Future<Uri?> Function(LinuxOptions options)? _portalPicker;
  final DBusClient Function() _sessionBus;
  final int? Function() _appWindow;
  final Future<ProcessResult> Function(
    String executable,
    List<String> arguments,
  )
  _runProcess;

  @override
  Future<PickedLocation?> pick({
    PickOptions? options,
    PickedLocation? initialDirectory,
  }) async {
    final opts = options is LinuxOptions ? options : const LinuxOptions();
    final folder = switch (initialDirectory?.uri) {
      final uri? when uri.scheme == 'file' => uri.toFilePath(),
      _ => null,
    };
    for (final picker in [
      () => _pickWithPortal(opts, folder),
      () => _pickWithZenity(opts, folder),
      () => _pickWithKdialog(opts, folder),
    ]) {
      try {
        final uri = await picker();
        if (uri == null) return null;
        return IOPickedLocation(uri);
      } on _PickerUnavailableException {
        continue;
      }
    }
    throw UnsupportedError(
      'No directory picker is available. Install xdg-desktop-portal, '
      'zenity or kdialog.',
    );
  }

  Future<Uri?> _pickWithPortal(LinuxOptions opts, String? folder) async {
    try {
      final portalPicker = _portalPicker;
      return portalPicker != null
          ? await portalPicker(opts)
          : await _pickWithDbusPortal(opts, folder);
    } catch (_) {
      throw _PickerUnavailableException();
    }
  }

  Future<Uri?> _pickWithDbusPortal(LinuxOptions opts, String? folder) async {
    final client = _sessionBus();
    try {
      final object = DBusRemoteObject(
        client,
        name: 'org.freedesktop.portal.Desktop',
        path: DBusObjectPath('/org/freedesktop/portal/desktop'),
      );

      // Connects, so the client's unique name is known.
      await client.ping();

      // Subscribe to the Response signal before calling OpenFile, on the
      // request path the portal will use, as the portal docs recommend. The
      // portal may send Response before its reply to OpenFile arrives.
      final token = 'dir_picker_${DateTime.now().microsecondsSinceEpoch}';
      final sender = client.uniqueName.substring(1).replaceAll('.', '_');
      final requestPath = DBusObjectPath(
        '/org/freedesktop/portal/desktop/request/$sender/$token',
      );
      Future<DBusSignal> responseOn(DBusObjectPath path) => DBusSignalStream(
        client,
        interface: 'org.freedesktop.portal.Request',
        name: 'Response',
        path: path,
      ).first;
      final expectedResponse = responseOn(requestPath);

      final result = await object.callMethod(
        'org.freedesktop.portal.FileChooser',
        'OpenFile',
        [
          // Makes the dialog modal to the app window. Only X11 window IDs
          // are supported; on Wayland the dialog has no parent.
          DBusString(switch (_appWindow()) {
            final xid? => 'x11:${xid.toRadixString(16)}',
            null => '',
          }), // parent_window
          DBusString(opts.title), // title
          DBusDict.stringVariant({
            'handle_token': DBusString(token),
            'directory': DBusBoolean(true),
            'modal': DBusBoolean(true),
            'accept_label': DBusString(opts.acceptLabel),
            // A NUL-terminated byte string, per the FileChooser spec.
            if (folder != null)
              'current_folder': DBusArray.byte([...utf8.encode(folder), 0]),
          }),
        ],
        replySignature: DBusSignature('o'),
      );

      // Portals older than 0.9 ignore handle_token and return another path.
      final handlePath = result.returnValues[0].asObjectPath();
      final DBusSignal signal;
      if (handlePath == requestPath) {
        signal = await expectedResponse;
      } else {
        expectedResponse.ignore();
        signal = await responseOn(handlePath);
      }

      // 0 = success, 1 = cancelled, 2 = ended some other way. The GTK backend
      // sends 2 when the user closes the dialog (Esc or the close button), so
      // both 1 and 2 are a cancel.
      final response = signal.values[0].asUint32();
      if (response != 0) return null;

      final results = signal.values[1].asStringVariantDict();
      final uris = results['uris']?.asStringArray().toList();
      if (uris == null || uris.isEmpty) return null;

      final uri = Uri.parse(uris.first);
      return Uri.directory(uri.toFilePath());
    } finally {
      await client.close();
    }
  }

  Future<Uri?> _pickWithZenity(LinuxOptions opts, String? folder) async {
    try {
      final result = await _runProcess('zenity', [
        '--file-selection',
        '--directory',
        '--title=${opts.title}',
        // No --ok-label: zenity 4 rejects it for file selection (exit 255).
        // A trailing slash makes zenity open inside the folder.
        if (folder != null)
          '--filename=${folder.endsWith('/') ? folder : '$folder/'}',
      ]);
      final path = _dialogResult('zenity', result);
      return path == null ? null : Uri.directory(path);
    } on ProcessException {
      throw _PickerUnavailableException();
    }
  }

  Future<Uri?> _pickWithKdialog(LinuxOptions opts, String? folder) async {
    try {
      final result = await _runProcess('kdialog', [
        '--title',
        opts.title,
        '--getexistingdirectory',
        folder ?? Platform.environment['HOME'] ?? '/',
      ]);
      final path = _dialogResult('kdialog', result);
      return path == null ? null : Uri.directory(path);
    } on ProcessException {
      throw _PickerUnavailableException();
    }
  }

  /// Reads the picked path from a zenity or kdialog run. Exit code 1 means the
  /// user cancelled; any other non-zero code is an error, such as zenity's 5
  /// (timeout) or 255 (unexpected error). zenity also exits with 1 when it
  /// can't open a display, so that case still reads as a cancel.
  static String? _dialogResult(String tool, ProcessResult result) {
    if (result.exitCode == 1) return null;
    if (result.exitCode != 0) {
      final stderr = (result.stderr as String).trim();
      throw Exception(
        'PICKER_ERROR: $tool exited with code ${result.exitCode}'
        '${stderr.isEmpty ? '' : ': $stderr'}',
      );
    }
    final path = (result.stdout as String).trim();
    return path.isEmpty ? null : path;
  }

  @override
  Future<List<FileSystemEntry>> listEntries(
    PickedLocation location, {
    bool recursive = false,
  }) => streamEntries(location, recursive: recursive).toList();

  @override
  Stream<FileSystemEntry> streamEntries(
    PickedLocation location, {
    bool recursive = false,
  }) {
    final uri = location.uri;
    if (uri == null) {
      return Stream.error(
        ArgumentError.value(
          location,
          'location',
          'listEntries requires a native picked location with a URI.',
        ),
      );
    }

    return streamIoEntries(Directory.fromUri(uri), recursive: recursive);
  }

  @override
  Future<String> persist(PickedLocation location) async =>
      persistIoLocation(location);

  @override
  Future<PickedLocation?> restore(String token) => restoreIoLocation(token);

  @override
  Future<void> release(String token) async {}
}
