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

  @override
  Future<PickedLocation?> pick({PickOptions? options}) async => null;
}
