## dir_picker

<p align="left">
  <a href="https://github.com/vanvixi/dir_picker.flutter"><img src="https://img.shields.io/badge/platform-Android%20%7C%20iOS%20%7C%20macOS%20%7C%20Windows%20%7C%20Linux%20%7C%20Web-blue.svg" alt="Platform"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/license-MIT-purple.svg" alt="License: MIT"></a>
</p>

A Flutter plugin for picking a directory across all platforms using native system dialogs. Returns a `PickedLocation?` — null if the user cancelled, and can list entries from a previously picked directory with `DirPicker.listEntries()`.

## Features

- 📁 **All Platforms** – Android, iOS, macOS, Windows, Linux, and Web
- ⚡ **Native Performance** – Powered by FFI (iOS/macOS/Windows) and JNI (Android) for near-zero overhead
- 🎨 **Customizable Dialogs** – Platform-specific options for title, button labels, and more
- 🔗 **Persistent Permissions** – Android SAF persistent URI access across reboots
- 🐧 **Linux Portals** – XDG Desktop Portal with zenity/kdialog fallback

If you want to say thank you, star us on GitHub or like us on pub.dev.

## Installation

First, follow the [package installation instructions](https://pub.dev/packages/dir_picker/install) and add
`dir_picker` to your app.

## Quick Start

### Platform Setup

<details>
<summary><b>Android Configuration</b></summary>

**Supported:** API 21+ (Android 5.0+)

No configuration needed. The plugin uses the Storage Access Framework (`Intent.ACTION_OPEN_DOCUMENT_TREE`), which grants URI access through the system picker UI — no manifest permissions required.

</details>

<details>
<summary><b>iOS Configuration</b></summary>

**Supported:** iOS 13.0+

No configuration needed. The plugin uses `UIDocumentPickerViewController`, which is available without extra entitlements.

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

If none are available, the pick call throws. To install a fallback manually:

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

**Browser support:** Chrome 86+ and Edge 86+. Not supported in Firefox or Safari.

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
```

Options for other platforms are silently ignored — only the one matching the current platform is applied.

### AndroidOptions

| Parameter       | Type   | Default | Description                                                                                                    |
|-----------------|--------|---------|----------------------------------------------------------------------------------------------------------------|
| `shouldPersist` | `bool` | `true`  | Take persistable URI permission so the app retains access across reboots (SAF `takePersistableUriPermission`). |

### MacosOptions

| Parameter     | Type     | Default                | Description                                                      |
|---------------|----------|------------------------|------------------------------------------------------------------|
| `acceptLabel` | `String` | `'Select'`             | Label for the confirmation button (`NSOpenPanel.prompt`).        |
| `message`     | `String` | `'Choose a directory'` | Descriptive text shown inside the panel (`NSOpenPanel.message`). |

### LinuxOptions

| Parameter     | Type     | Default              | Description                                                     |
|---------------|----------|----------------------|-----------------------------------------------------------------|
| `title`       | `String` | `'Select Directory'` | Window title of the dialog.                                     |
| `acceptLabel` | `String` | `'Select'`           | Label for the confirmation button (XDG Portal and zenity only). |

### WindowsOptions

| Parameter     | Type     | Default              | Description                                                          |
|---------------|----------|----------------------|----------------------------------------------------------------------|
| `title`       | `String` | `'Select Directory'` | Window title of the dialog (`IFileDialog::SetTitle`).                |
| `acceptLabel` | `String` | `'Select'`           | Label for the confirmation button (`IFileDialog::SetOkButtonLabel`). |

## Core Concepts

### Return value

| Result                 | Meaning                                                                                           |
|------------------------|---------------------------------------------------------------------------------------------------|
| `IOPickedLocation`     | Native platforms — use `.uri` to get the selected directory URI.                                  |
| `WebPickedLocation`    | Web — use `.handle` (`FileSystemDirectoryHandle`) to access directory contents. `.uri` is `null`. |
| `null`                 | The user cancelled.                                                                               |

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

## API Reference

### `DirPicker.pick`

```dart
static Future<PickedLocation?> pick({PickOptions? options})
```

Returns a `PickedLocation` (either `IOPickedLocation` or `WebPickedLocation`), or `null` if the user cancelled.

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

### `PickedLocation`

Base type returned by `DirPicker.pick()`.

| Type                | Platform                       | Notes                                                                 |
|---------------------|--------------------------------|-----------------------------------------------------------------------|
| `IOPickedLocation`  | Android, iOS, macOS, Windows, Linux | Provides a non-null `uri`.                                            |
| `WebPickedLocation` | Web                            | Provides a `FileSystemDirectoryHandle`; `uri` is always `null`.       |

### `FileSystemEntry`

Model returned by `DirPicker.listEntries()`.

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

## Platform Support

| Android | iOS | macOS | Windows | Linux | Web |
| :-----: | :-: | :---: | :-----: | :---: | :-: |
|   ✅    | ✅  |  ✅   |   ✅    |  ✅   | ✅  |

**Minimum versions:**

- Flutter ≥ 3.44.0
- Dart SDK ≥ 3.12.0
- Kotlin 2.1.0
- Swift 5.9
- Android API 21+
- iOS 13.0+
- macOS 10.15+
- Windows 10+
- Web: Chrome/Edge 86+

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License — see [LICENSE](LICENSE) file for details.
