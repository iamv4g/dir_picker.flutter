import 'dart:async';

import 'package:dir_picker/dir_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'DirPicker.listEntries forwards to the platform implementation',
    () async {
      final platform = _FakePlatform();
      DirPickerPlatform.instance = platform;
      final location = IOPickedLocation(Uri.directory('/tmp/example'));

      final entries = await DirPicker.listEntries(location, recursive: true);

      expect(platform.location, same(location));
      expect(platform.recursive, isTrue);
      expect(entries, hasLength(1));
      expect(entries.single.relativePath, 'child.txt');
    },
  );

  group('DirPicker.pick', () {
    test('rejects a second call while a picker is open', () async {
      final platform = _FakePlatform();
      DirPickerPlatform.instance = platform;

      final first = DirPicker.pick();
      await expectLater(
        DirPicker.pick(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('ALREADY_ACTIVE'),
          ),
        ),
      );
      expect(platform.pickCalls, 1);

      final picked = IOPickedLocation(Uri.directory('/tmp/picked'));
      platform.pickResult.complete(picked);
      expect(await first, same(picked));
    });

    test('allows a new call after the previous one completes', () async {
      final platform = _FakePlatform();
      DirPickerPlatform.instance = platform;

      final first = DirPicker.pick();
      platform.pickResult.complete(null);
      expect(await first, isNull);

      platform.pickResult = Completer()..completeError(Exception('boom'));
      await expectLater(DirPicker.pick(), throwsException);

      platform.pickResult = Completer()..complete(null);
      expect(await DirPicker.pick(), isNull);
      expect(platform.pickCalls, 3);
    });
  });

  test('WebPickedLocation can be checked for on every platform', () {
    // Compiling this file on native is the real check: the stub must declare
    // the same members as the web class, or the README example breaks.
    String describe(PickedLocation location) => switch (location) {
      WebPickedLocation() => 'web:${location.name}:${location.handle}',
      _ => 'native:${location.uri}',
    };

    expect(
      describe(IOPickedLocation(Uri.directory('/tmp/example'))),
      'native:file:///tmp/example/',
    );
  });

  group('value equality', () {
    test('FileSystemEntry compares all fields', () {
      FileSystemEntry entry({int? size = 5}) => FileSystemEntry(
        name: 'b.txt',
        relativePath: 'sub/b.txt',
        isDirectory: false,
        uri: Uri.file('/tmp/sub/b.txt'),
        size: size,
        lastModified: DateTime.fromMillisecondsSinceEpoch(1000),
      );

      expect(entry(), entry());
      expect(entry().hashCode, entry().hashCode);
      expect(entry(), isNot(entry(size: 6)));
      expect({entry(), entry()}, hasLength(1));
    });

    test('IOPickedLocation compares URIs', () {
      final a = IOPickedLocation(Uri.directory('/tmp/a'));

      expect(a, IOPickedLocation(Uri.directory('/tmp/a')));
      expect(a.hashCode, IOPickedLocation(Uri.directory('/tmp/a')).hashCode);
      expect(a, isNot(IOPickedLocation(Uri.directory('/tmp/b'))));
      expect(<PickedLocation>{
        a,
        IOPickedLocation(Uri.directory('/tmp/a')),
      }, hasLength(1));
    });
  });

  test('FileSystemEntry.fromJson parses nullable fields', () {
    final entry = FileSystemEntry.fromJson({
      'name': 'nested',
      'relativePath': 'folder/nested',
      'isDirectory': true,
      'uri': null,
      'size': null,
      'lastModified': null,
    });

    expect(entry.name, 'nested');
    expect(entry.relativePath, 'folder/nested');
    expect(entry.isDirectory, isTrue);
    expect(entry.uri, isNull);
    expect(entry.size, isNull);
    expect(entry.lastModified, isNull);
  });
}

class _FakePlatform extends DirPickerPlatform {
  PickedLocation? location;
  bool recursive = false;

  @override
  Future<List<FileSystemEntry>> listEntries(
    PickedLocation location, {
    bool recursive = false,
  }) async {
    this.location = location;
    this.recursive = recursive;
    return const [
      FileSystemEntry(
        name: 'child.txt',
        relativePath: 'child.txt',
        isDirectory: false,
      ),
    ];
  }

  Completer<PickedLocation?> pickResult = Completer();
  int pickCalls = 0;

  @override
  Future<PickedLocation?> pick({PickOptions? options}) {
    pickCalls++;
    return pickResult.future;
  }
}
