import 'package:dir_picker/dir_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toString shows the code and the message', () {
    expect(
      const DirPickerException('LIST_ERROR', 'Permission denied').toString(),
      'DirPickerException(LIST_ERROR): Permission denied',
    );
    expect(
      const DirPickerException('LIST_ERROR').toString(),
      'DirPickerException(LIST_ERROR)',
    );
  });

  test(
    'is an Exception, so existing `on Exception` handlers still catch it',
    () {
      expect(const DirPickerException('PICKER_ERROR'), isA<Exception>());
    },
  );
}
