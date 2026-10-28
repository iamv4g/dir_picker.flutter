## Description

<!-- What does this PR change, and why? Link the issue it resolves, e.g. "Fixes #123". -->

Fixes #

## Type of change

<!-- Check all that apply. The PR title should follow Conventional Commits with a platform scope,
     e.g. `feat(darwin): …`, `fix(android): …`, `fix(windows): …`, `refactor(web): …`, `docs: …`. -->

- [ ] 🐛 Bug fix (non-breaking change that fixes an issue)
- [ ] ✨ New feature (non-breaking change that adds functionality)
- [ ] 💥 Breaking change (public API, behaviour or minimum platform/SDK version changes)
- [ ] ♻️ Refactor / performance (no behaviour change)
- [ ] 📝 Documentation
- [ ] 🔧 Build / CI / tooling

## Affected platforms

- [ ] Android
- [ ] iOS
- [ ] macOS
- [ ] Windows
- [ ] Linux
- [ ] Web
- [ ] Dart layer only (shared / platform interface)

## How was this tested?

<!-- Devices, OS versions and browsers you ran the example app on, and which flows you exercised
     (pick, cancel, pick twice, listEntries recursive/non-recursive, symlinks, unreadable folders…). -->

| Platform | Device / OS / browser | Result |
| -------- | --------------------- | ------ |
|          |                       |        |

## Checklist

<!-- CI already runs `dart format`, `flutter analyze`, `flutter test` (VM and Chrome) and pana, and, for
     the platforms your change touches, builds the example and runs `example/integration_test` on macOS,
     Linux and Windows. The items below are what it can't check. -->

- [ ] Added or updated tests in `test/` or `example/integration_test/` (or explained above why it can't be tested)
- [ ] Ran `example/integration_test` on an iOS simulator if the Swift `listEntries` changed (CI doesn't run iOS)
- [ ] Native code formatted (Swift follows `darwin/.swift-format`)
- [ ] Tested `pick()` in the `example/` app on every platform checked above (it needs a user, so CI can't)
- [ ] `CHANGELOG.md` updated for user-facing changes
- [ ] README updated if an API, option or setup step changed

<details>
<summary><b>Native bridge / cross-language changes</b> (check if relevant)</summary>

- [ ] Generated bindings were regenerated, not hand-edited (`dart run tool/ffigen.dart` / `dart run tool/jnigen.dart`)
- [ ] New Darwin functions are in `include/dir_picker_ffi.h`, the Swift `@_cdecl`, and the include list in `tool/ffigen.dart`
- [ ] Darwin port messages still follow `[0, string]` / `[1]` / `[2, code, message]` (`platforms/darwin/port_message.dart`)
- [ ] `listEntries` JSON still matches `FileSystemEntry.fromJson` on every platform (`/` separators, root excluded, NFC names)
- [ ] Web/IO stubs (`io_stub.dart`, `web_stub.dart`, `web_picked_location_stub.dart`) updated for new/renamed platform classes or public types
- [ ] SwiftPM (`Package.swift`) and CocoaPods (`dir_picker.podspec`) kept in sync for new sources or headers

</details>

## Screenshots / recordings

<!-- Optional: helpful for pickers and permission prompts. -->
