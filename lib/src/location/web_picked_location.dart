import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../dir_picker_exception.dart';
import '../options/pick_options.dart';
import 'picked_location.dart';

/// `queryPermission()` and `requestPermission()`, which only Chromium
/// browsers have.
extension on web.FileSystemHandle {
  external JSPromise<JSString> queryPermission(JSObject descriptor);
  external JSPromise<JSString> requestPermission(JSObject descriptor);
}

/// A [PickedLocation] on the web platform.
///
/// Wraps a [FileSystemDirectoryHandle] from the File System Access API.
/// Use [handle] to list or read files within the selected directory.
///
/// [uri] is always `null` — browsers restrict access to the full filesystem
/// path for security reasons. Use [name] to get the directory name.
class WebPickedLocation extends PickedLocation {
  WebPickedLocation(this.handle);

  final web.FileSystemDirectoryHandle handle;

  /// The name of the selected directory.
  String get name => handle.name;

  /// Whether the page can use the directory now with [mode], without asking
  /// the user.
  ///
  /// A location from `DirPicker.pick` has access. One from `DirPicker.restore`
  /// keeps it only while another tab of the site still has it, or when the
  /// user chose "Allow on every visit" in Chrome. Otherwise call
  /// [requestAccess] from a button.
  ///
  /// It is about permission only: a folder that was deleted still returns
  /// `true`, and reading it throws a [DirPickerException] with
  /// [DirPickerException.listError].
  ///
  /// Browsers without `queryPermission()`, such as Firefox and Safari,
  /// always return `true`. They have no `showDirectoryPicker()`, so their
  /// only directory handles come from the origin private file system, which
  /// is the site's own storage and is always readable and writable, with no
  /// permission to ask for. `false` there would make an app show an "allow
  /// access" button that can never succeed, and throwing would make every
  /// app check the browser first.
  Future<bool> hasAccess({
    WebPermissionMode mode = WebPermissionMode.read,
  }) async {
    if (!handle.has('queryPermission')) return true;
    final state = await handle.queryPermission(_descriptor(mode)).toDart;
    return state.toDart == 'granted';
  }

  /// Asks the user for access to the directory with [mode] if the page
  /// doesn't have it yet, and returns whether it has it now.
  ///
  /// The browser only shows the prompt for a user gesture, so call it from a
  /// click handler, for example the `onPressed` of a button. Called without
  /// one, it throws a [DirPickerException] with
  /// [DirPickerException.platformError]. Returns `false` when the user
  /// denies access.
  ///
  /// Browsers without `requestPermission()`, such as Firefox and Safari,
  /// return `true` without a prompt, for the same reason as [hasAccess].
  Future<bool> requestAccess({
    WebPermissionMode mode = WebPermissionMode.read,
  }) async {
    if (!handle.has('requestPermission')) return true;
    try {
      final state = await handle.requestPermission(_descriptor(mode)).toDart;
      return state.toDart == 'granted';
    } catch (e, stackTrace) {
      if (e is Error) rethrow;
      Error.throwWithStackTrace(
        DirPickerException(DirPickerException.platformError, e.toString()),
        stackTrace,
      );
    }
  }

  @override
  Uri? get uri => null;

  @override
  String toString() => 'WebPickedLocation(name: $name)';
}

JSObject _descriptor(WebPermissionMode mode) =>
    JSObject()..['mode'] = mode.name.toJS;
