import 'dart:io';

import 'package:dir_picker/dir_picker.dart';
import 'package:dir_picker/src/platforms/io_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('dir_picker_token'));
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('the token restores the same location', () async {
    final location = IOPickedLocation(temp.uri);

    final token = persistIoLocation(location);

    expect(token, temp.uri.toString());
    expect(await restoreIoLocation(token), location);
  });

  test('restores null once the directory is deleted', () async {
    final token = persistIoLocation(IOPickedLocation(temp.uri));
    temp.deleteSync();

    expect(await restoreIoLocation(token), isNull);
  });

  test('restores null for a token that is not a file URI', () async {
    expect(await restoreIoLocation('content://com.example/tree/1'), isNull);
    expect(await restoreIoLocation('not a uri at all'), isNull);
    expect(await restoreIoLocation('::'), isNull);
  });

  test('persist rejects a location that is not a file URI', () {
    expect(
      () => persistIoLocation(
        IOPickedLocation(Uri.parse('content://com.example/tree/1')),
      ),
      throwsArgumentError,
    );
  });
}
