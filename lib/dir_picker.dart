import 'src/location/file_system_entry.dart';
import 'src/location/picked_location.dart';
import 'src/options/pick_options.dart';
import 'src/platform_interface/dir_picker_platform.dart';

export 'src/location/file_system_entry.dart';
export 'src/location/picked_location.dart';
// WebPickedLocation — web only, stub on native.
export 'src/location/web_picked_location.dart'
    if (dart.library.io) 'src/location/web_picked_location_stub.dart';
export 'src/options/pick_options.dart';
export 'src/platform_interface/dir_picker_platform.dart' show DirPickerPlatform;
// IO platforms (Windows, Linux, Android, Darwin) — or their stubs on web.
export 'src/platforms/io_platforms.dart'
    if (dart.library.js_interop) 'src/platforms/io_stub.dart';
// Web platform — or its stub on non-web platforms.
export 'src/platforms/web/dir_picker_web.dart'
    if (dart.library.io) 'src/platforms/web_stub.dart';

class DirPicker {
  DirPicker._();

  /// Picks a directory and returns a [PickedLocation], or `null` if cancelled.
  ///
  /// ## Platform behavior
  ///
  /// - **Android**: Uses the Storage Access Framework (`ACTION_OPEN_DOCUMENT_TREE`).
  ///   No manifest permissions required. Set [AndroidOptions.shouldPersist] to
  ///   retain access across reboots via persistable URI permission.
  ///
  /// - **iOS**: Uses `UIDocumentPickerViewController` to let the user pick a folder.
  ///
  /// - **macOS**: Uses `NSOpenPanel`. Requires the
  ///   `com.apple.security.files.user-selected.read-write` entitlement in your
  ///   app's `.entitlements` files. Customize with [MacosOptions].
  ///
  /// - **Windows**: Uses the COM `IFileOpenDialog` interface (Win32).
  ///   Customize the dialog title and button label with [WindowsOptions].
  ///
  /// - **Linux**: Uses the XDG Desktop Portal (`org.freedesktop.portal.FileChooser`)
  ///   with automatic fallback to `zenity` (GNOME) then `kdialog` (KDE).
  ///   Throws [UnsupportedError] if none of them is available.
  ///   Customize with [LinuxOptions].
  ///
  /// - **Web**: Uses the File System Access API (`window.showDirectoryPicker()`).
  ///   Supported on Chrome 86+ and Edge 86+. Throws [UnsupportedError] on
  ///   Firefox and Safari. Returns a [WebPickedLocation] — [PickedLocation.uri]
  ///   is always `null` (browsers restrict path access); use
  ///   [WebPickedLocation.handle] (`FileSystemDirectoryHandle`) to access
  ///   directory contents. Requires `package:web` in your app's dependencies.
  static Future<PickedLocation?> pick({PickOptions? options}) =>
      DirPickerPlatform.instance.pick(options: options);

  /// Lists entries inside a previously picked directory.
  ///
  /// Returns a flat list of descendants under [location]. The picked root
  /// itself is excluded from the results.
  ///
  /// When [recursive] is `false`, only immediate children are returned.
  /// When `true`, all nested descendants are returned.
  ///
  /// A symbolic link is reported as what it points to: a link to a directory
  /// has [FileSystemEntry.isDirectory] set, and a broken link is a
  /// non-directory without a size. Links are never followed, so a recursive
  /// listing doesn't include what is inside a linked directory. A
  /// subdirectory that can't be read is listed, but its contents are skipped.
  static Future<List<FileSystemEntry>> listEntries(
    PickedLocation location, {
    bool recursive = false,
  }) => DirPickerPlatform.instance.listEntries(location, recursive: recursive);
}
