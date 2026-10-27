import 'dart:convert';

import 'package:dir_picker/dir_picker.dart';
import 'package:dir_picker/src/platforms/darwin/port_message.dart';
import 'package:dir_picker/src/platforms/entries_json.dart';
import 'package:flutter_test/flutter_test.dart';

Matcher _throwsExceptionWith(String text) => throwsA(
  isA<Exception>().having((e) => e.toString(), 'toString()', contains(text)),
);

Matcher _throwsStateError(String message) =>
    throwsA(isA<StateError>().having((e) => e.message, 'message', message));

void main() {
  group('decodePickMessage', () {
    test('decodes a selected directory', () {
      final location = decodePickMessage([0, 'file:///Users/me/Projects/']);

      expect(location, isA<IOPickedLocation>());
      expect(location!.uri, Uri.parse('file:///Users/me/Projects/'));
    });

    test('decodes a cancellation as null', () {
      expect(decodePickMessage([1]), isNull);
    });

    test('turns an error message into an exception', () {
      expect(
        () => decodePickMessage([2, 'PLATFORM_ERROR', 'No root view']),
        _throwsExceptionWith('PLATFORM_ERROR: No root view'),
      );
    });

    test('rejects an unknown message type', () {
      expect(
        () => decodePickMessage([7]),
        _throwsStateError('Unknown message type: 7'),
      );
    });

    for (final message in <Object?>[
      null,
      'x',
      [],
      [0],
      [0, 42],
      [2, 'X'],
    ]) {
      test('rejects malformed message $message', () {
        expect(
          () => decodePickMessage(message),
          _throwsStateError('Invalid message format'),
        );
      });
    }
  });

  group('decodeListEntriesMessage', () {
    test('decodes the entries JSON', () {
      final json = jsonEncode([
        {
          'name': 'a.txt',
          'relativePath': 'a.txt',
          'isDirectory': false,
          'uri': 'file:///root/a.txt',
          'size': 2,
          'lastModified': 1700000000000,
        },
      ]);

      final entries = decodeListEntriesMessage([0, json]);

      expect(entries.single.relativePath, 'a.txt');
      expect(entries.single.size, 2);
    });

    test('turns an error message into an exception', () {
      expect(
        () => decodeListEntriesMessage([2, 'LIST_ERROR', 'Permission denied']),
        _throwsExceptionWith('LIST_ERROR: Permission denied'),
      );
    });

    test('rejects a cancellation, which listEntries never sends', () {
      expect(
        () => decodeListEntriesMessage([1]),
        _throwsStateError('Invalid message format'),
      );
    });
  });

  group('decodeEntriesJson', () {
    test('decodes files and directories', () {
      final entries = decodeEntriesJson(
        jsonEncode([
          {
            'name': 'b.txt',
            'relativePath': 'sub/b.txt',
            'isDirectory': false,
            'uri': 'content://tree/sub%2Fb.txt',
            // Native JSON encoders may write whole numbers as doubles.
            'size': 5.0,
            'lastModified': 1700000000000,
          },
          {
            'name': 'sub',
            'relativePath': 'sub',
            'isDirectory': true,
            'uri': 'content://tree/sub',
            'size': null,
            'lastModified': null,
          },
        ]),
      );

      expect(entries, hasLength(2));
      final [file, directory] = entries;
      expect(file.relativePath, 'sub/b.txt');
      expect(file.size, 5);
      expect(file.uri, Uri.parse('content://tree/sub%2Fb.txt'));
      expect(
        file.lastModified,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      expect(directory.isDirectory, isTrue);
      expect(directory.size, isNull);
      expect(directory.lastModified, isNull);
    });

    test('decodes an empty directory', () {
      expect(decodeEntriesJson('[]'), isEmpty);
    });
  });
}
