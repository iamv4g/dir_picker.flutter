// Stub for DirPickerWeb, used when compiling for non-web (IO) platforms.
import '../location/file_system_entry.dart';
import '../location/picked_location.dart';
import '../options/pick_options.dart';
import '../platform_interface/dir_picker_platform.dart';

class DirPickerWeb extends DirPickerPlatform {
  static void registerWith(dynamic registrar) =>
      DirPickerPlatform.instance = DirPickerWeb();
  @override
  Future<PickedLocation?> pick({PickOptions? options}) =>
      throw UnsupportedError('DirPicker is not supported on this platform.');
  @override
  Future<List<FileSystemEntry>> listEntries(
    PickedLocation location, {
    bool recursive = false,
  }) => throw UnsupportedError('DirPicker is not supported on this platform.');
}
