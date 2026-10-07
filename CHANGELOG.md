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
