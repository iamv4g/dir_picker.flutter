import 'package:dir_picker/dir_picker.dart';
import 'package:flutter_test/flutter_test.dart';

// Its own file, so nothing has registered a platform yet: plain `flutter
// test` doesn't run plugin registration.
void main() {
  test('DirPicker throws a StateError when no platform is registered', () {
    expect(
      () => DirPickerPlatform.instance,
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('has not been set'),
        ),
      ),
    );
    expect(DirPicker.pick(), throwsStateError);
  });
}
