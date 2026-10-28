import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../../location/file_system_entry.dart';
import '../../location/picked_location.dart';
import '../../location/web_picked_location.dart';
import '../../options/pick_options.dart';
import '../../platform_interface/dir_picker_platform.dart';

extension on web.Window {
  external JSPromise<web.FileSystemDirectoryHandle> showDirectoryPicker();
}

extension on web.FileSystemDirectoryHandle {
  external _AsyncIterator values();
}

bool get _supportsShowDirectoryPicker =>
    web.window.hasProperty('showDirectoryPicker'.toJS).toDart;

extension type _AsyncIterator._(JSObject _) implements JSObject {
  external JSPromise<_IteratorResult> next();
}

extension type _IteratorResult._(JSObject _) implements JSObject {
  external bool get done;
  external JSAny? get value;
}

/// DirPicker implementation for Web. (temporary CI scope test)
///
/// Uses the File System Access API (`window.showDirectoryPicker()`).
/// Supported in Chrome/Edge 86+. Throws [UnsupportedError] in Firefox/Safari.
/// Returns a [WebPickedLocation] wrapping the [FileSystemDirectoryHandle].
///
/// Note: [PickedLocation.uri] is always `null` on web — browsers do not
/// expose full filesystem paths. Use [WebPickedLocation.handle] to access
/// directory contents via the File System Access API.
class DirPickerWeb extends DirPickerPlatform {
  static void registerWith(dynamic registrar) {
    DirPickerPlatform.instance = DirPickerWeb();
  }

  @override
  Future<PickedLocation?> pick({PickOptions? options}) async {
    if (!_supportsShowDirectoryPicker) {
      throw UnsupportedError(
        'showDirectoryPicker() is not supported in this browser. '
        'Use Chrome or Edge 86+.',
      );
    }
    try {
      final handle = await web.window.showDirectoryPicker().toDart;
      return WebPickedLocation(handle);
    } catch (e) {
      // AbortError → user cancelled
      if (e.toString().contains('AbortError')) return null;
      rethrow;
    }
  }

  @override
  Future<List<FileSystemEntry>> listEntries(
    PickedLocation location, {
    bool recursive = false,
  }) async {
    if (!_supportsShowDirectoryPicker) {
      throw UnsupportedError(
        'File System Access API is not supported in this browser. '
        'Use Chrome or Edge 86+.',
      );
    }
    if (location is! WebPickedLocation) {
      throw ArgumentError.value(
        location,
        'location',
        'listEntries requires a WebPickedLocation on web.',
      );
    }

    return _listHandle(location.handle, recursive: recursive);
  }
}

Future<List<FileSystemEntry>> _listHandle(
  web.FileSystemDirectoryHandle handle, {
  required bool recursive,
  String parentPath = '',
}) async {
  final entries = <FileSystemEntry>[];
  final iterator = handle.values();

  while (true) {
    final result = await iterator.next().toDart;
    if (result.done) break;

    final item = result.value! as web.FileSystemHandle;
    final relativePath = _joinRelativePath(parentPath, item.name);

    if (item.kind == 'file') {
      final fileHandle = item as web.FileSystemFileHandle;
      final file = await fileHandle.getFile().toDart;
      entries.add(
        FileSystemEntry(
          name: item.name,
          relativePath: relativePath,
          isDirectory: false,
          uri: null,
          size: file.size,
          lastModified: DateTime.fromMillisecondsSinceEpoch(file.lastModified),
        ),
      );
      continue;
    }

    final directoryHandle = item as web.FileSystemDirectoryHandle;
    entries.add(
      FileSystemEntry(
        name: item.name,
        relativePath: relativePath,
        isDirectory: true,
        uri: null,
      ),
    );

    if (recursive) {
      entries.addAll(
        await _listHandle(
          directoryHandle,
          recursive: true,
          parentPath: relativePath,
        ),
      );
    }
  }

  return entries;
}

String _joinRelativePath(String parentPath, String name) =>
    parentPath.isEmpty ? name : '$parentPath/$name';
