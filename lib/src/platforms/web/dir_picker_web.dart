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
  external JSPromise<web.FileSystemDirectoryHandle> showDirectoryPicker([
    JSObject options,
  ]);
}

/// The `showDirectoryPicker()` options object. Unset options are left out:
/// the browser would turn a null `id` into the string "null" and reject a
/// null `startIn`.
///
/// A handle in [initialDirectory] takes precedence over [WebOptions.startIn].
JSObject _pickerOptions(WebOptions options, PickedLocation? initialDirectory) {
  final object = JSObject()..['mode'] = options.mode.name.toJS;
  if (options.id case final id?) {
    object['id'] = id.toJS;
  }
  if (initialDirectory is WebPickedLocation) {
    object['startIn'] = initialDirectory.handle;
  } else if (options.startIn case final startIn?) {
    object['startIn'] = startIn.name.toJS;
  }
  return object;
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

/// DirPicker implementation for Web.
///
/// Uses the File System Access API (`window.showDirectoryPicker()`).
/// Supported in Chrome/Edge 86+. [pick] throws [UnsupportedError] in
/// Firefox/Safari; [listEntries] works there for any directory handle.
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
  Future<PickedLocation?> pick({
    PickOptions? options,
    PickedLocation? initialDirectory,
  }) async {
    if (!_supportsShowDirectoryPicker) {
      throw UnsupportedError(
        'showDirectoryPicker() is not supported in this browser. '
        'Use Chrome or Edge 86+.',
      );
    }
    try {
      final handle = await web.window
          .showDirectoryPicker(
            _pickerOptions(
              options is WebOptions ? options : const WebOptions(),
              initialDirectory,
            ),
          )
          .toDart;
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
    // Only pick() needs showDirectoryPicker. Any directory handle can be
    // listed, such as one from the origin private file system, which Firefox
    // and Safari support.
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

/// Lists [handle], reading the files of each directory and the
/// subdirectories in parallel. Entries keep the browser's iteration order.
Future<List<FileSystemEntry>> _listHandle(
  web.FileSystemDirectoryHandle handle, {
  required bool recursive,
  String parentPath = '',
}) async {
  final pending = <Future<List<FileSystemEntry>>>[];
  final iterator = handle.values();

  while (true) {
    final result = await iterator.next().toDart;
    if (result.done) break;

    final item = result.value! as web.FileSystemHandle;
    final relativePath = _joinRelativePath(parentPath, item.name);

    if (item.kind == 'file') {
      pending.add(_fileEntry(item as web.FileSystemFileHandle, relativePath));
      continue;
    }

    final directory = FileSystemEntry(
      name: item.name,
      relativePath: relativePath,
      isDirectory: true,
      uri: null,
    );
    pending.add(
      recursive
          ? _listHandle(
              item as web.FileSystemDirectoryHandle,
              recursive: true,
              parentPath: relativePath,
            ).then((children) => [directory, ...children])
          : Future.value([directory]),
    );
  }

  return [for (final entries in await Future.wait(pending)) ...entries];
}

Future<List<FileSystemEntry>> _fileEntry(
  web.FileSystemFileHandle handle,
  String relativePath,
) async {
  final file = await handle.getFile().toDart;
  return [
    FileSystemEntry(
      name: handle.name,
      relativePath: relativePath,
      isDirectory: false,
      uri: null,
      size: file.size,
      lastModified: DateTime.fromMillisecondsSinceEpoch(file.lastModified),
    ),
  ];
}

String _joinRelativePath(String parentPath, String name) =>
    parentPath.isEmpty ? name : '$parentPath/$name';
