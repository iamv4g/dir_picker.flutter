// Stub for WebPickedLocation, used when compiling for non-web (IO) platforms.
import 'picked_location.dart';

/// Native stand-in for the web-only `WebPickedLocation`.
///
/// It lets cross-platform code check `location is WebPickedLocation` and read
/// [handle] and [name] without a conditional import. `DirPicker.pick` never
/// returns one on native platforms, so the check is always `false` there.
abstract class WebPickedLocation extends PickedLocation {
  WebPickedLocation._();

  /// Never available on native platforms.
  Never get handle;

  /// The name of the selected directory.
  String get name;
}
