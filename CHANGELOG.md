## Unreleased

* iOS/macOS: `listEntries` now returns `name` and `relativePath` in precomposed Unicode (NFC), like the other platforms. Before, names with accents such as `tài liệu` came back decomposed (NFD) and did not compare equal to Dart strings
* iOS/macOS: `listEntries(recursive: true)` now throws for a missing directory or a path that is not a directory. Before, it returned an empty list
* Linux: `pick()` now subscribes to the portal's `Response` signal before calling `OpenFile`, as the XDG portal docs recommend. Before, a `Response` that arrived before the method reply was lost and `pick()` never completed (#24)
* Linux: `pick()` now throws `Exception('PICKER_ERROR: …')` when the portal ends the request with an error (response 2), or when zenity or kdialog exit with a code other than 0 or 1. Before, these returned `null`, as if the user had cancelled (#25)
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
