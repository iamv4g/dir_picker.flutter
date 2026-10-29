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

  /// Shows the directory picker. See `DirPicker.pick`.
  ///
  /// Implementations should open in [initialDirectory] when the platform can,
  /// and ignore it otherwise.
  Future<PickedLocation?> pick({
    PickOptions? options,
    PickedLocation? initialDirectory,
  });

  Future<List<FileSystemEntry>> listEntries(
    PickedLocation location, {
    bool recursive = false,
  });

  /// Keeps access to [location] across app restarts. See `DirPicker.persist`.
  ///
  /// Not abstract, so implementations written before it was added still
  /// compile. They throw [UnimplementedError].
  Future<String> persist(PickedLocation location) async =>
      throw UnimplementedError('persist() has not been implemented.');

  /// Turns a token from [persist] back into a location. See
  /// `DirPicker.restore`.
  Future<PickedLocation?> restore(String token) async =>
      throw UnimplementedError('restore() has not been implemented.');

  /// Gives up the access a token from [persist] keeps. See
  /// `DirPicker.release`.
  Future<void> release(String token) async =>
      throw UnimplementedError('release() has not been implemented.');
}
