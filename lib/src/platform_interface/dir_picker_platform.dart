import '../location/file_system_entry.dart';
import '../location/picked_location.dart';
import '../options/pick_options.dart';

abstract class DirPickerPlatform {
  static DirPickerPlatform? _instance;

  /// The implementation for the current platform.
  ///
  /// Throws a [StateError] if no implementation has been registered, for
  /// example when `DirPicker` is used before the Flutter bindings are
  /// initialized, or from an isolate without plugin registration.
  static DirPickerPlatform get instance =>
      _instance ??
      (throw StateError(
        'DirPickerPlatform.instance has not been set. Make sure the plugin '
        'is registered (run the app with Flutter, which calls '
        'GeneratedPluginRegistrant) before calling DirPicker.',
      ));

  static set instance(DirPickerPlatform platform) => _instance = platform;

  Future<PickedLocation?> pick({PickOptions? options});

  Future<List<FileSystemEntry>> listEntries(
    PickedLocation location, {
    bool recursive = false,
  });
}
