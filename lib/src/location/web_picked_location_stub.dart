// Stub for WebPickedLocation, used when compiling for non-web (IO) platforms.
import '../options/pick_options.dart';
import 'picked_location.dart';

/// Native stand-in for the web-only `WebPickedLocation`.
///
/// It lets cross-platform code check `location is WebPickedLocation` and use
/// its members without a conditional import. `DirPicker.pick` never returns
/// one on native platforms, so the check is always `false` there.
abstract class WebPickedLocation extends PickedLocation {
  WebPickedLocation._();

  /// Never available on native platforms.
  Never get handle;

  /// The name of the selected directory.
  String get name;

  /// Whether the page can use the directory now with [mode].
  Future<bool> hasAccess({WebPermissionMode mode = WebPermissionMode.read});

  /// Asks the user for access to the directory with [mode].
  Future<bool> requestAccess({WebPermissionMode mode = WebPermissionMode.read});
}
