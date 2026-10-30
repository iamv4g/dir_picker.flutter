## dir_picker

<p align="left">
  <a href="https://github.com/iamv4g/dir_picker.flutter"><img src="https://img.shields.io/badge/platform-Android%20%7C%20iOS%20%7C%20macOS%20%7C%20Windows%20%7C%20Linux%20%7C%20Web-blue.svg" alt="Platform"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/license-MIT-purple.svg" alt="License: MIT"></a>
</p>

A Flutter plugin for picking a directory across all platforms using native system dialogs. `DirPicker.pick()` returns a `PickedLocation?` (null if the user cancelled). You can then list what's inside with `DirPicker.listEntries()` or `DirPicker.streamEntries()`, and keep access to the folder after the app restarts with `DirPicker.persist()`.

## Features

- 📁 **All Platforms** – Android, iOS, macOS, Windows, Linux, and Web
- ⚡ **Native Performance** – Powered by FFI (iOS/macOS/Windows) and JNI (Android) for near-zero overhead
- 🎨 **Customizable Dialogs** – Platform-specific options for title, button labels, and more, and an initial folder to open in
- 📜 **Directory Listing** – list a picked folder at once, or stream large trees in batches and stop early
- 🔗 **Persistent Access** – keep using a picked folder after the app restarts: persisted URI permissions on Android, bookmarks on iOS and macOS
- 🐧 **Linux Portals** – XDG Desktop Portal with zenity/kdialog fallback

If you want to say thank you, star us on GitHub or like us on pub.dev.

## Installation

First, follow the [package installation instructions](https://pub.dev/packages/dir_picker/install) and add
`dir_picker` to your app.

## Quick Start

### Platform Setup

<details>
<summary><b>Android Configuration</b></summary>

**Supported:** API 24+ (Android 7.0+)

No configuration needed. The plugin uses the Storage Access Framework (`Intent.ACTION_OPEN_DOCUMENT_TREE`), which grants URI access through the system picker UI — no manifest permissions required.

</details>

<details>
<summary><b>iOS Configuration</b></summary>

**Supported:** iOS 13.0+

No configuration needed. The plugin uses `UIDocumentPickerViewController`, which is available without extra entitlements.

The plugin ships a privacy manifest (`PrivacyInfo.xcprivacy`) that declares its file timestamp access (reasons `3B52.1` and `C617.1`), so App Store Connect sees it without changes to your app's own manifest. The same applies on macOS.

</details>

<details>
<summary><b>macOS Configuration</b></summary>

**Supported:** macOS 10.15+

Add the following entitlement to `macos/Runner/Release.entitlements` and `macos/Runner/DebugProfile.entitlements`:

```xml
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

</details>

<details>
<summary><b>Windows Configuration</b></summary>

**Supported:** Windows 10+

No configuration needed. The plugin uses the native `IFileOpenDialog` COM API.

</details>

<details>
<summary><b>Linux Configuration</b></summary>

The plugin tries the following dialog backends in order:

1. **XDG Desktop Portal** – Works on all modern desktop environments via D-Bus (`org.freedesktop.portal.FileChooser`)
2. **zenity** – GNOME fallback
3. **kdialog** – KDE fallback

If none are available, `pick()` throws an `UnsupportedError`. To install a fallback manually:

```bash
# GNOME
sudo apt install zenity

# KDE
sudo apt install kdialog
```

</details>

<details>
<summary><b>Web Configuration</b></summary>

No configuration needed. The plugin uses the [File System Access API](https://developer.mozilla.org/en-US/docs/Web/API/Window/showDirectoryPicker).

**Browser support:** `pick()` needs Chrome 86+ or Edge 86+; it throws `UnsupportedError` in Firefox and Safari. `listEntries()` works in any browser for a `WebPickedLocation` you create from a `FileSystemDirectoryHandle`, for example one from the origin private file system (`navigator.storage.getDirectory()`).

Works with both the JavaScript (`flutter build web`) and WebAssembly (`flutter build web --wasm`) compilers.

> **Note:** On web, `pick()` returns a `WebPickedLocation` wrapping a `FileSystemDirectoryHandle`. Use `.handle` to access directory contents via the File System Access API. `PickedLocation.uri` is always `null` on web — browsers do not expose full filesystem paths. Requires `package:web` in your app's dependencies to work with the handle directly.

</details>

### Basic Usage

```dart
import 'package:dir_picker/dir_picker.dart';

final PickedLocation? location = await DirPicker.pick();

if (location == null) {
  print('Cancelled');
} else if (location is WebPickedLocation) {
  // Web: use handle to access directory contents via File System Access API
  // Requires package:web in your app's dependencies
  final handle = location.handle; // FileSystemDirectoryHandle
  print('Selected directory: ${location.name}');
} else {
  // Native (Android, iOS, macOS, Windows, Linux)
  print('Selected: ${location.uri}');
}
```

### List directory entries

```dart
final location = await DirPicker.pick();
if (location == null) return;

final entries = await DirPicker.listEntries(location, recursive: true);
for (final entry in entries) {
  print('${entry.relativePath} (dir: ${entry.isDirectory})');
}
```

For large trees, `streamEntries` emits the same entries while the folder is still being read, so the app can show progress or stop early. Cancelling the subscription stops the walk:

```dart
await for (final entry in DirPicker.streamEntries(location, recursive: true)) {
  if (entry.name == 'pubspec.yaml') break; // stops reading the folder
}
```

### Open the picker where the user was last time

```dart
final next = await DirPicker.pick(initialDirectory: previousLocation);
```

`initialDirectory` is a hint: where a platform can't use it, the picker opens in its default place.

| Platform | Supported `initialDirectory` |
|----------|------------------------------|
| Android  | API 26+. A `content://` location from an earlier pick, or an entry's `uri` (`EXTRA_INITIAL_URI`). |
| iOS      | iOS 13+. A `file://` location (`UIDocumentPickerViewController.directoryURL`). |
| macOS    | A `file://` location (`NSOpenPanel.directoryURL`). |
| Windows  | A `file://` location (`IFileDialog::SetFolder`). |
| Linux    | A `file://` location: XDG portal `current_folder`, zenity `--filename`, kdialog's start folder. |
| Web      | A `WebPickedLocation` (`startIn`). It takes precedence over `WebOptions.startIn`. |

### Android: get back a pick lost to a destroyed Activity

Android can destroy the app's Activity, or kill its process, while the system picker is open (low memory, "Don't keep activities"). The app restarts when the user picks, and the `pick()` call that opened the picker never completes. Call `retrieveLostPick` at startup to get that folder:

```dart
final lost = await DirPicker.retrieveLostPick(); // null on other platforms
if (lost != null) {
  // Handle it like the result of pick().
}
```

Each lost pick is returned once. `shouldPersist` isn't applied to it, so call `DirPicker.persist` if you need to keep access.

### Keep access to a folder after the app restarts

```dart
final prefs = SharedPreferencesAsync();

// After a pick: keep access and save the token.
final token = await DirPicker.persist(location);
await prefs.setString('workspace', token);

// On a later launch: get the folder back without asking the user.
final saved = await prefs.getString('workspace');
final restored = saved == null ? null : await DirPicker.restore(saved);
if (restored == null) {
  // Deleted, revoked or released: ask the user to pick again.
}

// When the app no longer needs it.
await DirPicker.release(token);
await prefs.remove('workspace');
```

| Platform | Token | What `persist` keeps |
|----------|-------|----------------------|
| Android  | The `content://` URI | A persistable URI permission. Android keeps at most 128 per app (512 from Android 11) and drops the oldest, so `release` folders you no longer need. |
| iOS      | Bookmark data (base64) | A bookmark. `restore` opens access again until `release` or the app exits. |
| macOS    | Security-scoped bookmark data (base64) | A security-scoped bookmark. Needs the same `com.apple.security.files.user-selected.read-write` entitlement as `pick`. |
| Windows, Linux | The `file://` URI | Nothing: the path stays usable. `restore` returns `null` once the folder is gone. |
| Web      | – | Not supported (`UnsupportedError`). Store `WebPickedLocation.handle` in IndexedDB instead. |

A bookmark follows the folder when it's moved or renamed, but the token goes stale. Call `persist` on the restored location and save the new token, as the example app does.

`PickOptions.android(shouldPersist: true)` still takes the permission during `pick`. `persist` does the same afterwards, and works on every platform except web.

## Platform Options

Pass a `PickOptions` to `DirPicker.pick()` to customize the dialog for the current platform:

```dart
final location = await DirPicker.pick(
  options: PickOptions.android(shouldPersist: true),
);

final location = await DirPicker.pick(
  options: PickOptions.macos(acceptLabel: 'Choose', message: 'Select a project folder'),
);

final location = await DirPicker.pick(
  options: PickOptions.linux(title: 'Select Folder', acceptLabel: 'Choose'),
);

final location = await DirPicker.pick(
  options: PickOptions.windows(title: 'Select Folder', acceptLabel: 'Choose'),
);

final location = await DirPicker.pick(
  options: PickOptions.web(
    mode: WebPermissionMode.readwrite,
    id: 'exports',
    startIn: WebStartIn.documents,
  ),
);
```

Options for other platforms are silently ignored — only the one matching the current platform is applied.

### AndroidOptions

| Parameter       | Type   | Default | Description                                                                                                    |
|-----------------|--------|---------|----------------------------------------------------------------------------------------------------------------|
| `shouldPersist` | `bool` | `false` | Take persistable URI permission so the app retains access across reboots (SAF `takePersistableUriPermission`). |

### MacosOptions

| Parameter     | Type     | Default                | Description                                                      |
|---------------|----------|------------------------|------------------------------------------------------------------|
| `acceptLabel` | `String` | `'Select'`             | Label for the confirmation button (`NSOpenPanel.prompt`).        |
| `message`     | `String` | `'Choose a directory'` | Descriptive text shown inside the panel (`NSOpenPanel.message`). |

### LinuxOptions

| Parameter     | Type     | Default              | Description                                                     |
|---------------|----------|----------------------|-----------------------------------------------------------------|
| `title`       | `String` | `'Select Directory'` | Window title of the dialog.                                     |
| `acceptLabel` | `String` | `'Select'`           | Label for the confirmation button (XDG Portal only).            |

### WindowsOptions

| Parameter     | Type     | Default              | Description                                                          |
|---------------|----------|----------------------|----------------------------------------------------------------------|
| `title`       | `String` | `'Select Directory'` | Window title of the dialog (`IFileDialog::SetTitle`).                |
| `acceptLabel` | `String` | `'Select'`           | Label for the confirmation button (`IFileDialog::SetOkButtonLabel`). |

### WebOptions

Passed to `window.showDirectoryPicker()`.

| Parameter | Type                | Default                    | Description                                                                                                  |
|-----------|---------------------|----------------------------|--------------------------------------------------------------------------------------------------------------|
| `mode`    | `WebPermissionMode` | `WebPermissionMode.read`   | Access to request. `readwrite` lets the handle create, change and delete files without asking again.         |
| `id`      | `String?`           | `null`                     | Remembers the last folder picked for this purpose. At most 32 letters, digits, `_` or `-`.                     |
| `startIn` | `WebStartIn?`       | `null`                     | Well-known folder to open in (`desktop`, `documents`, `downloads`, `music`, `pictures`, `videos`) when there's no remembered folder for `id`. |

## Core Concepts

### Return value

| Result                 | Meaning                                                                                           |
|------------------------|---------------------------------------------------------------------------------------------------|
| `IOPickedLocation`     | Native platforms — use `.uri` to get the selected directory URI.                                  |
| `WebPickedLocation`    | Web — use `.handle` (`FileSystemDirectoryHandle`) to access directory contents. `.uri` is `null`. |
| `null`                 | The user cancelled.                                                                               |

Only one picker can be open at a time. Calling `pick()` again before the previous call completes throws an `Exception` whose message starts with `ALREADY_ACTIVE`.

### Native Mechanisms

| Platform | Mechanism                                        |
|----------|--------------------------------------------------|
| Android  | SAF (`Intent.ACTION_OPEN_DOCUMENT_TREE`) via JNI |
| iOS      | `UIDocumentPickerViewController` via FFI         |
| macOS    | `NSOpenPanel` via FFI                            |
| Windows  | `IFileOpenDialog` (COM) via pure Dart FFI        |
| Linux    | XDG Desktop Portal → zenity → kdialog            |
| Web      | `window.showDirectoryPicker()` (JS interop)      |

## Common Use Cases

### Simple directory pick (native)

```dart
final location = await DirPicker.pick();
if (location != null) {
  print('Selected: ${location.uri}');
}
```

### Simple directory pick (web)

```dart
import 'package:dir_picker/dir_picker.dart';
import 'package:web/web.dart' as web; // required to use FileSystemDirectoryHandle

final location = await DirPicker.pick();
if (location is WebPickedLocation) {
  final web.FileSystemDirectoryHandle handle = location.handle;
  // list files, read contents, etc.
}
```

### Custom dialog labels

```dart
final location = await DirPicker.pick(
  options: PickOptions.macos(
    acceptLabel: 'Use This Folder',
    message: 'Select the folder to import from',
  ),
);

// or on Linux/Windows:
final location = await DirPicker.pick(
  options: PickOptions.linux(
    title: 'Import Folder',
    acceptLabel: 'Use This Folder',
  ),
);
```

### Android — enable persistent permission

```dart
final location = await DirPicker.pick(
  options: PickOptions.android(shouldPersist: true),
);
```

To keep access on every platform, use [`DirPicker.persist`](#keep-access-to-a-folder-after-the-app-restarts) instead.

## API Reference

### `DirPicker.pick`

```dart
static Future<PickedLocation?> pick({PickOptions? options, PickedLocation? initialDirectory})
```

Returns a `PickedLocation` (either `IOPickedLocation` or `WebPickedLocation`), or `null` if the user cancelled.

`initialDirectory` opens the picker in that folder where the platform supports it (see [Open the picker where the user was last time](#open-the-picker-where-the-user-was-last-time)).

`options` is a `PickOptions` sealed class — pass the platform-specific subclass using its factory constructor (e.g. `PickOptions.android(...)`, `PickOptions.macos(...)`). Options for other platforms are ignored.

### `DirPicker.listEntries`

```dart
static Future<List<FileSystemEntry>> listEntries(
  PickedLocation location, {
  bool recursive = false,
})
```

Lists files and directories inside a previously picked location.

Behavior:

- Returns a flat list of descendants under the picked root.
- Excludes the picked root itself.
- Lists only immediate children when `recursive` is `false`.
- Lists all nested descendants when `recursive` is `true`.
- Does not guarantee output ordering.
- Completes only once every entry has been read. For large trees, use `streamEntries`.

### `DirPicker.streamEntries`

```dart
static Stream<FileSystemEntry> streamEntries(
  PickedLocation location, {
  bool recursive = false,
})
```

Emits the same entries as `listEntries` while the directory is being read: in batches of 200 on Android, iOS and macOS, one directory at a time on web, and one by one on Windows and Linux. Cancelling the subscription stops the walk. A failure to read `location` itself is emitted as an error.

### `DirPicker.persist`, `DirPicker.restore`, `DirPicker.release`

```dart
static Future<String> persist(PickedLocation location)
static Future<PickedLocation?> restore(String token)
static Future<void> release(String token)
```

`persist` keeps access to a picked or restored location and returns a token to save. `restore` returns the location with access restored, or `null` when the token no longer gives access. `release` gives up that access. See [Keep access to a folder after the app restarts](#keep-access-to-a-folder-after-the-app-restarts). All three throw `UnsupportedError` on web.

### `DirPicker.retrieveLostPick`

```dart
static Future<PickedLocation?> retrieveLostPick()
```

Returns the folder from a `pick()` whose result came back after Android destroyed the app's Activity, once, or `null`. Always `null` on other platforms. See [Android: get back a pick lost to a destroyed Activity](#android-get-back-a-pick-lost-to-a-destroyed-activity).

### `PickedLocation`

Base type returned by `DirPicker.pick()`.

| Type                | Platform                       | Notes                                                                 |
|---------------------|--------------------------------|-----------------------------------------------------------------------|
| `IOPickedLocation`  | Android, iOS, macOS, Windows, Linux | Provides a non-null `uri`.                                            |
| `WebPickedLocation` | Web                            | Provides a `FileSystemDirectoryHandle`; `uri` is always `null`.       |

### `FileSystemEntry`

Model returned by `DirPicker.listEntries()` and `DirPicker.streamEntries()`.

| Field          | Type        | Description                                                    |
|----------------|-------------|----------------------------------------------------------------|
| `name`         | `String`    | Basename of the entry.                                         |
| `relativePath` | `String`    | Path relative to the picked root, always using `/` separators. |
| `isDirectory`  | `bool`      | Whether the entry is a directory.                              |
| `uri`          | `Uri?`      | Native URI when available; always `null` on web.               |
| `size`         | `int?`      | File size in bytes; `null` for directories or when unavailable. |
| `lastModified` | `DateTime?` | Last modified timestamp when available.                        |

### `PickOptions`

Platform-specific options passed to `DirPicker.pick()`.

| Factory                 | Platform | Purpose                                                        |
|-------------------------|----------|----------------------------------------------------------------|
| `PickOptions.android()` | Android  | Controls whether SAF URI permission should be persisted.       |
| `PickOptions.macos()`   | macOS    | Customizes the open panel accept label and message.            |
| `PickOptions.linux()`   | Linux    | Customizes dialog title and accept label.                      |
| `PickOptions.windows()` | Windows  | Customizes dialog title and accept label.                      |
| `PickOptions.web()`     | Web      | Sets the access mode, remembered-folder `id` and start folder. |

## Platform Support

| Android | iOS | macOS | Windows | Linux | Web |
| :-----: | :-: | :---: | :-----: | :---: | :-: |
|   ✅    | ✅  |  ✅   |   ✅    |  ✅   | ✅  |

**Minimum versions:**

- Flutter ≥ 3.44.0
- Dart SDK ≥ 3.12.0
- Kotlin Gradle Plugin 2.0.0+ (enforced by Flutter 3.44)
- Swift 5.9
- Android API 24+
- iOS 13.0+
- macOS 10.15+
- Windows 10+
- Web: Chrome/Edge 86+ for `pick()`; `listEntries()` works in any browser with a `FileSystemDirectoryHandle`

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License — see [LICENSE](LICENSE) file for details.
