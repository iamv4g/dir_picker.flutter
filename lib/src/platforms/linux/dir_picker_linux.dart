import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../location/file_system_entry.dart';
import '../../location/picked_location.dart';
import '../../options/pick_options.dart';
import '../../platform_interface/dir_picker_platform.dart';
import '../io_entries.dart';

/// Thrown when a picker method is not available on the current system
/// (e.g. portal daemon not running, CLI tool not installed).
/// Distinct from user cancellation, which returns null.
class _PickerUnavailableException implements Exception {}

/// The portal's `Response` signal reported an error rather than a result or
/// a cancel.
class _PortalResponseError implements Exception {
  _PortalResponseError(this.response);

  final int response;
}

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
/// cancelled — the fallback chain stops immediately. A picker that is present
/// but fails throws `Exception('PICKER_ERROR: …')`. If no method is available,
/// [pick] throws an [UnsupportedError].
class DirPickerLinux extends DirPickerPlatform {
  DirPickerLinux() : this.withBackends();

  /// Creates an instance with replaceable picker backends.
  ///
  /// [portalPicker] replaces the XDG Desktop Portal call. Throwing from it
  /// marks the portal as unavailable. [sessionBus] replaces
  /// [DBusClient.session] for the real portal call. [runProcess] replaces
  /// [Process.run] for the zenity and kdialog fallbacks.
  @visibleForTesting
  DirPickerLinux.withBackends({
    this._portalPicker,
    DBusClient Function()? sessionBus,
    Future<ProcessResult> Function(String executable, List<String> arguments)?
    runProcess,
  }) : _sessionBus = sessionBus ?? DBusClient.session,
       _runProcess = runProcess ?? Process.run;

  static void registerWith() {
    DirPickerPlatform.instance = DirPickerLinux();
  }

  final Future<Uri?> Function(LinuxOptions options)? _portalPicker;
  final DBusClient Function() _sessionBus;
  final Future<ProcessResult> Function(
    String executable,
    List<String> arguments,
  )
  _runProcess;

  @override
  Future<PickedLocation?> pick({PickOptions? options}) async {
    final opts = options is LinuxOptions ? options : const LinuxOptions();
    for (final picker in [
      () => _pickWithPortal(opts),
      () => _pickWithZenity(opts),
      () => _pickWithKdialog(opts),
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

  Future<Uri?> _pickWithPortal(LinuxOptions opts) async {
    try {
      return await (_portalPicker ?? _pickWithDbusPortal)(opts);
    } on _PortalResponseError catch (e) {
      throw Exception(
        'PICKER_ERROR: The XDG Desktop Portal ended the request with '
        'response ${e.response}',
      );
    } catch (_) {
      throw _PickerUnavailableException();
    }
  }

  Future<Uri?> _pickWithDbusPortal(LinuxOptions opts) async {
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
          DBusString(''), // parent_window
          DBusString(opts.title), // title
          DBusDict.stringVariant({
            'handle_token': DBusString(token),
            'directory': DBusBoolean(true),
            'modal': DBusBoolean(true),
            'accept_label': DBusString(opts.acceptLabel),
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

      // 0 = success, 1 = cancelled, 2 = ended some other way (an error).
      final response = signal.values[0].asUint32();
      if (response == 1) return null;
      if (response != 0) throw _PortalResponseError(response);

      final results = signal.values[1].asStringVariantDict();
      final uris = results['uris']?.asStringArray().toList();
      if (uris == null || uris.isEmpty) return null;

      final uri = Uri.parse(uris.first);
      return Uri.directory(uri.toFilePath());
    } finally {
      await client.close();
    }
  }

  Future<Uri?> _pickWithZenity(LinuxOptions opts) async {
    try {
      final result = await _runProcess('zenity', [
        '--file-selection',
        '--directory',
        '--title=${opts.title}',
        '--ok-label=${opts.acceptLabel}',
      ]);
      final path = _dialogResult('zenity', result);
      return path == null ? null : Uri.directory(path);
    } on ProcessException {
      throw _PickerUnavailableException();
    }
  }

  Future<Uri?> _pickWithKdialog(LinuxOptions opts) async {
    try {
      final result = await _runProcess('kdialog', [
        '--title',
        opts.title,
        '--getexistingdirectory',
        Platform.environment['HOME'] ?? '/',
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
  }) async {
    final uri = location.uri;
    if (uri == null) {
      throw ArgumentError.value(
        location,
        'location',
        'listEntries requires a native picked location with a URI.',
      );
    }

    return listIoEntries(Directory.fromUri(uri), recursive: recursive);
  }
}
