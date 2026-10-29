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

  static bool _isPicking = false;

  /// Picks a directory and returns a [PickedLocation], or `null` if cancelled.
  ///
  /// The picker opens in [initialDirectory] when the platform supports it,
  /// usually a location from an earlier [pick]. Where it isn't supported, or
  /// the location doesn't fit the platform, it's ignored and the picker opens
  /// in its default place:
  ///
  /// | Platform | Support |
  /// |----------|---------|
  /// | Android  | API 26+. A `content://` location from an earlier pick (`EXTRA_INITIAL_URI`). |
  /// | iOS      | iOS 13+. A `file://` location (`directoryURL`). |
  /// | macOS    | A `file://` location (`NSOpenPanel.directoryURL`). |
  /// | Windows  | A `file://` location (`IFileDialog::SetFolder`). |
  /// | Linux    | A `file://` location: XDG portal `current_folder`, zenity `--filename`, kdialog's start folder. |
  /// | Web      | A [WebPickedLocation] (`startIn`). It takes precedence over [WebOptions.startIn]. |
  ///
  /// Only one picker can be open at a time. Calling [pick] again before the
  /// previous call completes throws an [Exception] starting with
  /// `ALREADY_ACTIVE`, and the open picker is left as it is.
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
  /// - **Windows**: Uses the COM `IFileOpenDialog` interface (Win32), owned
  ///   by the app's window so it stays on top of it and is modal.
  ///   Customize the dialog title and button label with [WindowsOptions].
  ///
  /// - **Linux**: Uses the XDG Desktop Portal (`org.freedesktop.portal.FileChooser`)
  ///   with automatic fallback to `zenity` (GNOME) then `kdialog` (KDE).
  ///   On X11, the portal dialog is modal to the app's window. On Wayland,
  ///   and with zenity or kdialog, it opens as a separate window.
  ///   Throws [UnsupportedError] if none of them is available.
  ///   Customize with [LinuxOptions].
  ///
  /// - **Web**: Uses the File System Access API (`window.showDirectoryPicker()`).
  ///   Supported on Chrome 86+ and Edge 86+. Throws [UnsupportedError] on
  ///   Firefox and Safari. Returns a [WebPickedLocation] — [PickedLocation.uri]
  ///   is always `null` (browsers restrict path access); use
  ///   [WebPickedLocation.handle] (`FileSystemDirectoryHandle`) to access
  ///   directory contents. Requires `package:web` in your app's dependencies.
  ///   Customize the access mode and starting folder with [WebOptions].
  static Future<PickedLocation?> pick({
    PickOptions? options,
    PickedLocation? initialDirectory,
  }) async {
    if (_isPicking) {
      throw Exception('ALREADY_ACTIVE: A directory picker is already open');
    }
    _isPicking = true;
    try {
      return await DirPickerPlatform.instance.pick(
        options: options,
        initialDirectory: initialDirectory,
      );
    } finally {
      _isPicking = false;
    }
  }

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

  /// Keeps access to [location] after the app restarts, and returns a token
  /// to save, for example in shared preferences. Pass the token to [restore]
  /// on a later launch to use the folder again without asking the user.
  ///
  /// [location] has to come from [pick] or [restore]. What the token holds
  /// and keeps depends on the platform:
  ///
  /// | Platform | Token | Keeps |
  /// |----------|-------|-------|
  /// | Android  | The `content://` URI | A persistable URI permission (`takePersistableUriPermission`). The system keeps at most 128 of them per app (512 from Android 11) and drops the oldest, so [release] the ones you no longer need. |
  /// | iOS      | Bookmark data (base64) | A bookmark of the folder. Access is restored when the bookmark is resolved. |
  /// | macOS    | Security-scoped bookmark data (base64) | A security-scoped bookmark. A sandboxed app needs the `com.apple.security.files.user-selected.read-write` entitlement, as for [pick]. |
  /// | Windows, Linux | The `file://` URI | Nothing: these apps aren't sandboxed, so the path stays usable. |
  /// | Web      | – | Not supported, throws [UnsupportedError]. |
  ///
  /// Throws an [Exception] starting with `PERSIST_ERROR` when the platform
  /// refuses, for example on Android when the app no longer has access to
  /// the folder.
  static Future<String> persist(PickedLocation location) =>
      DirPickerPlatform.instance.persist(location);

  /// Returns the location a [persist] token points to, with access to it
  /// restored, or `null` when the token no longer gives access: the folder
  /// was deleted or moved out of reach, the permission was revoked or
  /// [release]d, or the token isn't valid on this platform.
  ///
  /// On iOS and macOS a bookmark can go stale when the folder is moved or
  /// renamed. It still resolves, so call [persist] on the restored location
  /// and save the new token.
  ///
  /// Throws [UnsupportedError] on web.
  static Future<PickedLocation?> restore(String token) =>
      DirPickerPlatform.instance.restore(token);

  /// Gives up the access a [persist] token keeps, for a folder the app no
  /// longer needs:
  ///
  /// - **Android**: releases the persisted permission. [restore] then returns
  ///   `null` for the token.
  /// - **iOS, macOS**: a bookmark can't be revoked, so delete the token you
  ///   saved. This ends the access that [restore] (and on iOS, [pick])
  ///   started for the folder, which otherwise lasts until the app exits.
  /// - **Windows, Linux**: does nothing.
  ///
  /// Throws [UnsupportedError] on web.
  static Future<void> release(String token) =>
      DirPickerPlatform.instance.release(token);
}
