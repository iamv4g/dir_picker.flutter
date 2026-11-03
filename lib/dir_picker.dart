import 'src/dir_picker_exception.dart';
import 'src/location/file_system_entry.dart';
import 'src/location/picked_location.dart';
import 'src/options/pick_options.dart';
import 'src/platform_interface/dir_picker_platform.dart';

export 'src/dir_picker_exception.dart';
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
  /// previous call completes throws a [DirPickerException] with
  /// [DirPickerException.alreadyActive], and the open picker is left as it
  /// is. Other picker failures throw a [DirPickerException] too.
  ///
  /// ## Platform behavior
  ///
  /// - **Android**: Uses the Storage Access Framework (`ACTION_OPEN_DOCUMENT_TREE`).
  ///   No manifest permissions required. Call [persist] on the result to
  ///   keep access across restarts.
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
      throw const DirPickerException(
        DirPickerException.alreadyActive,
        'A directory picker is already open',
      );
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

  /// Returns the folder from a [pick] whose result came back after Android
  /// destroyed the app's Activity, or `null` when there is none.
  ///
  /// Android can destroy the Activity while the system picker is open: under
  /// memory pressure, with "Don't keep activities" on, or on a configuration
  /// change the Activity doesn't handle. With the default `FlutterActivity`
  /// the engine goes with it, so the [pick] that opened the picker never
  /// completes and the app restarts. Call this at startup, for example in
  /// `initState` of the first screen, to get the folder the user picked:
  ///
  /// ```dart
  /// final lost = await DirPicker.retrieveLostPick();
  /// if (lost != null) openWorkspace(lost);
  /// ```
  ///
  /// Each lost pick is returned once. Call [persist] on it if the app needs
  /// to keep access. Other platforms always return `null`.
  static Future<PickedLocation?> retrieveLostPick() =>
      DirPickerPlatform.instance.retrieveLostPick();

  /// Lists entries inside a previously picked directory.
  ///
  /// Returns a flat list of descendants under [location]. The picked root
  /// itself is excluded from the results.
  ///
  /// When [recursive] is `false`, only immediate children are returned.
  /// When `true`, all nested descendants are returned.
  ///
  /// The list completes only once every entry has been read. For a large
  /// tree, [streamEntries] emits entries as they are read and can be stopped
  /// early.
  ///
  /// A symbolic link is reported as what it points to: a link to a directory
  /// has [FileSystemEntry.isDirectory] set, and a broken link is a
  /// non-directory without a size. Links are never followed, so a recursive
  /// listing doesn't include what is inside a linked directory. A
  /// subdirectory that can't be read is listed, but its contents are skipped.
  /// A failure to read [location] itself throws a [DirPickerException] with
  /// [DirPickerException.listError].
  static Future<List<FileSystemEntry>> listEntries(
    PickedLocation location, {
    bool recursive = false,
  }) => DirPickerPlatform.instance.listEntries(location, recursive: recursive);

  /// Lists the same entries as [listEntries], as a stream that emits them
  /// while the directory is still being read.
  ///
  /// Use it for large trees: the app can show progress, and cancelling the
  /// subscription (for example `break` in an `await for`) stops the walk, so
  /// it never holds every entry at once.
  ///
  /// ```dart
  /// await for (final entry in DirPicker.streamEntries(location, recursive: true)) {
  ///   if (entry.name == 'pubspec.yaml') break;
  /// }
  /// ```
  ///
  /// Entries arrive in batches on Android, iOS and macOS. A failure to read
  /// [location] itself is emitted as a [DirPickerException] and closes the
  /// stream. Pausing
  /// the subscription buffers entries but doesn't pause the walk.
  static Stream<FileSystemEntry> streamEntries(
    PickedLocation location, {
    bool recursive = false,
  }) =>
      DirPickerPlatform.instance.streamEntries(location, recursive: recursive);

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
  /// | Web      | A random key | The `FileSystemDirectoryHandle`, in the plugin's IndexedDB database. Persisting the same folder again returns the same token. |
  ///
  /// On web the browser decides whether the restored folder can be read
  /// without asking again; see [restore].
  /// Throws a [DirPickerException] with [DirPickerException.persistError]
  /// when the platform refuses, for example on Android when the app no longer has access to
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
  /// On web the handle comes back, but the browser may not let the page use
  /// it yet: Chrome keeps access while another tab of the site has it, or
  /// for good when the user chose "Allow on every visit". Check
  /// [WebPickedLocation.hasAccess], and if it's `false`, call
  /// [WebPickedLocation.requestAccess] from a button before reading the
  /// folder; until then [listEntries] throws a [DirPickerException] with
  /// [DirPickerException.listError]. A folder that was deleted still restores
  /// on web and fails the same way.
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
  /// - **Web**: deletes the stored handle. [restore] then returns `null` for
  ///   the token.
  static Future<void> release(String token) =>
      DirPickerPlatform.instance.release(token);

  /// Returns the tokens of the folders the system keeps access to for the
  /// app, as [persist] returns them, so the app can [release] the ones it no
  /// longer has saved.
  ///
  /// Android and web keep such a list. On Android it holds the persisted
  /// permissions, at
  /// most 128 per app (512 from Android 11), and drops the oldest when the
  /// app takes more. A token the app didn't save, for example because the
  /// app was killed right after [persist], still takes a place until it is
  /// released:
  ///
  /// ```dart
  /// final saved = await prefs.getString('workspace');
  /// for (final token in await DirPicker.persistedTokens()) {
  ///   if (token != saved) await DirPicker.release(token);
  /// }
  /// ```
  ///
  /// The list has every folder (SAF tree) permission the app holds, including
  /// ones taken by other code in the app, so release only tokens you know are
  /// yours. Permissions for single documents aren't listed.
  ///
  /// On web it holds the handles [persist] stored, which only `dir_picker`
  /// writes. Other platforms keep nothing for the app (a bookmark on iOS and
  /// macOS is only the token the app saved), so they return an empty list.
  static Future<List<String>> persistedTokens() =>
      DirPickerPlatform.instance.persistedTokens();
}
