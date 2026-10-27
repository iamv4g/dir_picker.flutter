import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../../location/file_system_entry.dart';
import '../../location/picked_location.dart';
import '../../options/pick_options.dart';
import '../../platform_interface/dir_picker_platform.dart';

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
/// cancelled — the fallback chain stops immediately. If no method is
/// available, [pick] throws an [UnsupportedError].
class DirPickerLinux extends DirPickerPlatform {
  DirPickerLinux() : this.withBackends();

  /// Creates an instance with replaceable picker backends.
  ///
  /// [portalPicker] replaces the XDG Desktop Portal call. Throwing from it
  /// marks the portal as unavailable. [runProcess] replaces [Process.run] for
  /// the zenity and kdialog fallbacks.
  @visibleForTesting
  DirPickerLinux.withBackends({
    this._portalPicker,
    Future<ProcessResult> Function(String executable, List<String> arguments)?
    runProcess,
  }) : _runProcess = runProcess ?? Process.run;

  static void registerWith() {
    DirPickerPlatform.instance = DirPickerLinux();
  }

  final Future<Uri?> Function(LinuxOptions options)? _portalPicker;
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
    } catch (_) {
      throw _PickerUnavailableException();
    }
  }

  Future<Uri?> _pickWithDbusPortal(LinuxOptions opts) async {
    DBusClient? client;
    try {
      client = DBusClient.session();

      final object = DBusRemoteObject(
        client,
        name: 'org.freedesktop.portal.Desktop',
        path: DBusObjectPath('/org/freedesktop/portal/desktop'),
      );

      final token = 'dir_picker_${DateTime.now().millisecondsSinceEpoch}';

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

      final handlePath = result.returnValues[0].asObjectPath();

      final handleObject = DBusRemoteObject(
        client,
        name: 'org.freedesktop.portal.Desktop',
        path: handlePath,
      );

      final signals = DBusRemoteObjectSignalStream(
        object: handleObject,
        interface: 'org.freedesktop.portal.Request',
        name: 'Response',
      );

      await for (final signal in signals) {
        final response = signal.values[0].asUint32();
        if (response != 0) return null; // 1=cancelled, 2=error

        final results = signal.values[1].asStringVariantDict();
        final uris = results['uris']?.asStringArray().toList();
        if (uris == null || uris.isEmpty) return null;

        final uri = Uri.parse(uris.first);
        return Uri.directory(uri.toFilePath());
      }

      return null;
    } finally {
      await client?.close();
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
      if (result.exitCode != 0) return null;
      final path = (result.stdout as String).trim();
      return path.isEmpty ? null : Uri.directory(path);
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
      if (result.exitCode != 0) return null;
      final path = (result.stdout as String).trim();
      return path.isEmpty ? null : Uri.directory(path);
    } on ProcessException {
      throw _PickerUnavailableException();
    }
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

    final directory = Directory.fromUri(uri);
    final entries = <FileSystemEntry>[];

    await for (final entity in directory.list(
      recursive: recursive,
      followLinks: false,
    )) {
      final stat = await entity.stat();
      final relativePath = p.posix.normalize(
        p.posix.relative(entity.path, from: directory.path),
      );
      entries.add(
        FileSystemEntry(
          name: p.posix.basename(relativePath),
          relativePath: relativePath,
          isDirectory: stat.type == FileSystemEntityType.directory,
          uri: entity.uri,
          size: stat.type == FileSystemEntityType.file ? stat.size : null,
          lastModified: stat.modified,
        ),
      );
    }

    return entries;
  }
}
