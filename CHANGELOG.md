## 0.6.0

* **Breaking:** for custom `DirPickerPlatform` implementations only, `pick()` takes a new `initialDirectory` parameter. Apps that call `DirPicker` are not affected
* Add `initialDirectory` to `DirPicker.pick()`, so the picker opens in a folder from an earlier pick: `EXTRA_INITIAL_URI` on Android 8+, `directoryURL` on iOS 13+ and macOS, `IFileDialog::SetFolder` on Windows, `current_folder`/`--filename`/the start folder on Linux, and `startIn` on the web. Platforms that can't use the given location ignore it. The example app reopens the last picked folder (#27)
* Add `DirPicker.persist`, `DirPicker.restore` and `DirPicker.release` to keep using a picked folder after the app restarts: persisted URI permissions on Android, bookmarks on iOS, security-scoped bookmarks on macOS, and the path on Windows and Linux. Not supported on web. On Android, `release` gives back a persisted permission, so apps can stay under the system's per-app limit (#31, part of #32)
* Add `DirPicker.streamEntries`, which emits the entries of `listEntries` while the folder is still being read, in batches of 200 on Android, iOS and macOS. Cancelling the subscription stops the walk. `listEntries` is now built on it (#28)
* Android: add `DirPicker.retrieveLostPick()`. When Android destroys the Activity or kills the process while the picker is open, the picked folder is no longer dropped: call it at startup to get it, once. Other platforms return `null` (#22)
* `DirPickerPlatform` gains `persist`, `restore`, `release`, `streamEntries` and `retrieveLostPick`, with default implementations (`UnimplementedError` for the first three, the result of `listEntries` as a stream, and `null`), so existing custom implementations still compile
* iOS: `pick()` keeps the security scope of the picked folder open until `release` or the app exits, so later `listEntries` calls use the URL the picker returned
* iOS/macOS: add a privacy manifest (`PrivacyInfo.xcprivacy`) declaring the file timestamp access in `listEntries` (reasons `3B52.1` and `C617.1`). Before, App Store Connect could flag apps that use the plugin with ITMS-91053 (#51)
* Windows: the folder dialog is now owned by the app's window, so it stays on top of it and the window can't be used until it closes. Before, it opened as a separate top-level window (#33)
* Linux: on X11, the XDG Desktop Portal dialog is now modal to the app's window (`parent_window`). On Wayland, and with the zenity and kdialog fallbacks, it still opens as a separate window (#33)
* Web: add `PickOptions.web(mode:, id:, startIn:)`, passed to `showDirectoryPicker()`. `mode: WebPermissionMode.readwrite` returns a handle that can write without asking again, `id` lets the browser remember the last folder per purpose, and `startIn` opens in a well-known folder (#34)
* Web: `listEntries` now reads files and subdirectories in parallel instead of awaiting each `getFile()` in turn (#34)
* Android: `listEntries` now reads each directory with one `DocumentsContract` query instead of going through `DocumentFile`, which queried every field of every child separately. Listing 2,040 entries in the Downloads provider went from about 136 s to 1.5 s on a Galaxy Note 9, with identical results. The `androidx.documentfile` dependency is gone (#35)
* `FileSystemEntry` and `IOPickedLocation` now have value equality (`==` and `hashCode`), so two listings of the same folder compare equal and locations work as `Set`/`Map` keys (#29)
* `DirPicker` now throws a `StateError` that says what to do when no platform implementation is registered. Before, release builds failed with a bare null-check error (#30)
* iOS/macOS: `listEntries` now returns `name` and `relativePath` in precomposed Unicode (NFC), like the other platforms. Before, names with accents such as `tài liệu` came back decomposed (NFD) and did not compare equal to Dart strings
* iOS/macOS: `listEntries(recursive: true)` now throws for a missing directory or a path that is not a directory. Before, it returned an empty list
* Linux: `pick()` now subscribes to the portal's `Response` signal before calling `OpenFile`, as the XDG portal docs recommend. Before, a `Response` that arrived before the method reply was lost and `pick()` never completed (#24)
* Linux: `pick()` now throws `Exception('PICKER_ERROR: …')` when zenity or kdialog exit with a code other than 0 or 1, such as zenity's 5 (timeout). Before, these returned `null`, as if the user had cancelled (#25)
* Linux: the zenity fallback works with zenity 4 (Ubuntu 24.04 and later). It no longer passes `--ok-label`, which zenity 4 rejects for file selection, so `LinuxOptions.acceptLabel` now only applies to the XDG Desktop Portal. Before, zenity 4 failed and `pick()` returned `null`
* Linux/Windows: `listEntries(recursive: true)` now skips the contents of a subdirectory it can't read, as iOS and macOS already did. Before, one unreadable folder made the whole call throw `PathAccessException` (#15)
* iOS/macOS: `listEntries` now reports a symbolic link as what it points to, as Linux and Windows do: a link to a directory has `isDirectory: true`, with the target's size and date. Before, it was `isDirectory: false`. Links are still not followed in recursive listings (#16)
* Windows: the folder dialog now only accepts file system folders, and keeps its default options (`FOS_PATHMUSTEXIST`, `FOS_NOCHANGEDIR`). Before, picking "This PC" or a Library returned `null`, as if the user had cancelled (#17)
* Windows: `pick()` now throws `Exception('PLATFORM_ERROR: <step> failed with HRESULT 0x…')` when a COM call fails. Before, every failure returned `null`; only an actual cancel does now (#18)
* Web: `listEntries` no longer requires `showDirectoryPicker`, so it works in Firefox and Safari for any `FileSystemDirectoryHandle`, such as one from the origin private file system. Only `pick()` throws `UnsupportedError` there (#23)
* `pick()` now throws `Exception('ALREADY_ACTIVE: …')` when called while another `pick()` is still open. Before, on Android and iOS, one of the two Futures never completed (#19)
* iOS: the picker is now presented from the top-most view controller, so `pick()` works while another view controller (a sheet, an alert, another plugin's modal) is presented. Before, UIKit ignored the request and the Future never completed (#20)
* Android: the picker is now launched on the main thread instead of a background thread (#21)
* Android: a pick in progress now survives a configuration change of the host Activity when the Flutter engine outlives it (cached engine, add-to-app). Before, the Future completed with `null` and the picked folder was dropped (#22)
* Android: a failure to launch the picker is reported as an error (`PICKER_ERROR`, `NO_ACTIVITY`) instead of `null`
* Android: the consumer ProGuard/R8 rules now only keep `com.iamv4g.dir_picker`. Before, they also kept all of `kotlinx.coroutines`, `kotlin.coroutines` and `kotlin.jvm.internal`, and turned on `-keepparameternames` for the whole app (#26)
* Android: the plugin's Kotlin package is now `com.iamv4g.dir_picker` (was `com.vanvixi.dir_picker`), matching the GitHub account rename. The Dart API is unchanged; update any R8/ProGuard rules or native code in your app that refer to the old package
* Repository, issue tracker and podspec links now point to `github.com/iamv4g`

## 0.5.1

* Fix `flutter build web --wasm`. The FFI/JNI implementations are now excluded with `dart.library.js_interop` instead of `dart.library.html`, which is false under dart2wasm (#4, authored by coco-de-dev)
* Linux: `pick()` now throws `UnsupportedError` when no XDG Desktop Portal, zenity or kdialog is available. Before, it returned `null`, which looked like a user cancel (#11)
* `WebPickedLocation` is now declared on native platforms too, so `location is WebPickedLocation` (as in the README) compiles everywhere. Before, it failed with "'WebPickedLocation' isn't a type" outside the web (#12)
* Allow `dbus` 0.8.x (#8)
* Format code with the current `dart format` and silence a lint in the generated JNI bindings (#7)
* Correct the Android minimum (API 24+) and the `AndroidOptions.shouldPersist` default (`false`) in the README, and note Wasm support (#6)

## 0.5.0

* **Breaking:** Raise minimum supported SDK to Flutter 3.44 / Dart 3.12
* Migrate Android to built-in Kotlin (no longer applies the Kotlin Gradle Plugin)

## 0.4.1

* Update document

## 0.4.0

* Add `DirPicker.listEntries()` to list files and directories from a previously picked location
* Add `FileSystemEntry` with `relativePath`, metadata, and nullable web `uri`
* **Breaking:** `DirPicker.pick()` now takes a single `PickOptions? options` parameter instead of separate per-platform named parameters (`androidOptions`, `linuxOptions`, `macosOptions`, `windowsOptions`)
* **Breaking:** Rename `SelectedLocation` → `PickedLocation`, `NativeLocation` → `IOPickedLocation`, `WebSelectedLocation` → `WebPickedLocation`
* Add `PickOptions` sealed class with platform-specific factory constructors: `PickOptions.android(...)`, `PickOptions.macos(...)`, `PickOptions.linux(...)`, `PickOptions.windows(...)`
* Migrate `jnigen.yaml` and `ffigen.yaml` to Dart scripts in `tool/` directory for better maintainability (#3, authored by alihassan143)
* Update `jni` dependency to `1.0.0` (#3, authored by alihassan143)
* Update `jnigen` dev dependency to `0.16.0` (#3, authored by alihassan143)
* Fix `ffigen` configuration to support latest API changes in `ffigen 20.1` (#3, authored by alihassan143)

### Migration guide

```dart
// Before
DirPicker.pick(androidOptions: AndroidOptions(shouldPersist: true));
DirPicker.pick(macosOptions: MacosOptions(acceptLabel: 'Open'));

// After
DirPicker.pick(options: PickOptions.android(shouldPersist: true));
DirPicker.pick(options: PickOptions.macos(acceptLabel: 'Open'));
```

```dart
// Before
if (location is NativeLocation) { ... }
if (location is WebSelectedLocation) { ... }

// After
if (location is IOPickedLocation) { ... }
if (location is WebPickedLocation) { ... }
```

## 0.3.1

* Add README usage examples for handling `WebSelectedLocation` on web and `NativeLocation` on native

## 0.3.0

* **Breaking:** `DirPicker.pick()` now returns `SelectedLocation?` instead of `Uri?`
* Add `SelectedLocation` abstract class with `NativeLocation` (native platforms) and `WebSelectedLocation` (web)
* Web: return `WebSelectedLocation` wrapping `FileSystemDirectoryHandle` — use `.handle` to access directory contents via the File System Access API
* Web: throw `UnsupportedError` on browsers that do not support `showDirectoryPicker()` (Firefox/Safari)

## 0.2.1

* Fix Swift Package Manager detection on pub.dev

## 0.2.0

* Add Swift Package Manager (SPM) support for iOS and macOS
* **Breaking:** Rename `MacosOptions.prompt` → `MacosOptions.acceptLabel` for consistency with other platforms
* Add `MacosOptions.message` parameter to customize the panel message
* Fix `AndroidOptions.shouldPersist` default value to `false`

## 0.1.0

* Initial version
