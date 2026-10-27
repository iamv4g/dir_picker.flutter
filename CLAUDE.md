# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`dir_picker` is a Flutter plugin package that gives one Dart API, `DirPicker.pick()` and `DirPicker.listEntries()`, backed by native directory pickers on Android, iOS, macOS, Windows, Linux and Web. It uses no method channels: every platform talks to native code through FFI, JNI, D-Bus/processes or JS interop. Requires Flutter ≥ 3.44 / Dart ≥ 3.12.

## Commands

```bash
flutter pub get                      # root package
flutter analyze                      # lints: package:flutter_lints/flutter.yaml
flutter test                         # unit tests (test/dir_picker_test.dart)
flutter test test/dir_picker_test.dart --plain-name 'FileSystemEntry.fromJson'   # single test

cd example && flutter run -d <device>   # manual testing; the example app is the only integration harness

dart run tool/ffigen.dart            # regenerate lib/src/platforms/darwin/native_bindings.g.dart
dart run tool/jnigen.dart            # regenerate lib/src/platforms/android/native_bindings.g.dart
```

`tool/jnigen.dart` first runs `./gradlew dir_picker:compileDebugKotlin` inside `example/android/`, then reads the compiled classes from `example/build/dir_picker/tmp/kotlin-classes/debug`. The example Android project has to build before you can regenerate the JNI bindings.

Never edit `*.g.dart` by hand. Change the native source (the C header or the Kotlin classes), add any new symbol or class to the include list in the `tool/*.dart` script, then regenerate.

## Architecture

### Platform selection via conditional exports

`lib/dir_picker.dart` is the only public library. It picks which implementations compile using conditional exports:
- `src/platforms/io_platforms.dart` (Windows/Linux/Android/Darwin) is swapped for `io_stub.dart` on web.
- `src/platforms/web/dir_picker_web.dart` is swapped for `web_stub.dart` on IO.
- `web_picked_location.dart` is swapped for `web_picked_location_stub.dart` on IO.

Each stub has to declare the same class names and `registerWith` signatures as the real implementation (web's `registerWith` takes a `registrar`). When you add a platform class or a public type, update the matching stub too, or the build on the other target breaks.

Registration: `pubspec.yaml` declares a `dartPluginClass` for every platform except web (`pluginClass: DirPickerWeb`). Each class's static `registerWith()` sets `DirPickerPlatform.instance`. `DirPickerPlatform` (`src/platform_interface/`) is a plain abstract class (not `plugin_platform_interface`). It has two methods: `pick` and `listEntries`.

### Per-platform bridges

| Platform | Dart side | Native side | Transport |
|---|---|---|---|
| iOS / macOS | `platforms/darwin/dir_picker_darwin.dart` | `darwin/dir_picker/Sources/dir_picker/*.swift` (shared source, `sharedDarwinSource: true`) | FFI `@_cdecl` functions from `include/dir_picker_ffi.h`, results posted back via `Dart_PostCObject_DL` to a `ReceivePort` |
| Android | `platforms/android/dir_picker_android.dart` | `android/src/main/kotlin/com/vanvixi/dir_picker/` | JNI via `package:jni`; Dart implements the `PickerCallback` / `ListEntriesCallback` Kotlin interfaces |
| Windows | `platforms/windows/dir_picker_windows.dart` | none, pure Dart FFI against `ole32.dll` COM `IFileOpenDialog` | FFI |
| Linux | `platforms/linux/dir_picker_linux.dart` | none | `package:dbus` XDG Portal → `zenity` → `kdialog` (falls through on `_PickerUnavailableException`) |
| Web | `platforms/web/dir_picker_web.dart` | none | `package:web` `showDirectoryPicker()`; returns `WebPickedLocation` (handle, `uri == null`) |

Cross-platform conventions to keep consistent when changing any bridge:
- **Darwin message protocol** (`DirPickerReporter.swift` ↔ `dir_picker_darwin.dart`): `[0, string]` success, `[1]` cancelled, `[2, code, message]` error. The reporter sends at most once.
- **`listEntries` payload**: every native side serializes to a JSON array of `{name, relativePath, isDirectory, uri, size, lastModified(ms epoch)}`, which Dart parses with `FileSystemEntry.fromJson`. `relativePath` uses `/` separators and the picked root is excluded.
- Errors come back to Dart as `Exception('$CODE: $message')`. Cancelling resolves to `null`.
- Darwin C-string args are copied synchronously in Swift, so Dart frees them right after the call.
- Android: `DirPickerPlugin` (ActivityAware) installs a `PickerHandler` into the static `DirPicker` companion. `DirPicker.pick` / `listEntries` run on `Dispatchers.IO` coroutines and report through the callback. Dart releases the JNI callback in `whenComplete`.

### Native build packaging

- Darwin supports both SwiftPM (`darwin/dir_picker/Package.swift`, enabled via `enable-swift-package-manager` in pubspec) and CocoaPods (`darwin/dir_picker.podspec`). Keep the two in sync when you add sources or headers. `DartApiDl` is a vendored C target that exposes `dart_api_dl.h` to Swift.
- Swift formatting follows `darwin/.swift-format` (4-space indent).
- Android is built with Gradle (`android/build.gradle`, Java/JVM 17, compileSdk 36).

## Release notes

User-facing changes go in `CHANGELOG.md` (newest version on top; breaking changes prefixed `**Breaking:**`). Bump `version` in `pubspec.yaml` and update `README.md` whenever an API or option changes.
