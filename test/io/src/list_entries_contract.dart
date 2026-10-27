import 'dart:io';

import 'package:dir_picker/dir_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Behavior every dart:io based `listEntries` implementation must have.
///
/// Builds this tree in a temp directory:
/// ```
/// a.txt        (2 bytes)
/// sub/
///   b.txt      (5 bytes)
///   nested/
/// ```
void listEntriesContract(
  DirPickerPlatform Function() createPlatform, {
  bool testSymlinks = false,
}) {
  late Directory root;
  late DirPickerPlatform platform;

  setUp(() async {
    platform = createPlatform();
    root = await Directory.systemTemp.createTemp('dir_picker_test');
    await File(p.join(root.path, 'a.txt')).writeAsString('hi');
    await Directory(p.join(root.path, 'sub', 'nested')).create(recursive: true);
    await File(p.join(root.path, 'sub', 'b.txt')).writeAsString('hello');
  });

  tearDown(() => root.delete(recursive: true));

  IOPickedLocation location() => IOPickedLocation(Uri.directory(root.path));

  test('lists only immediate children by default', () async {
    final entries = await platform.listEntries(location());

    expect(
      entries.map((e) => e.relativePath),
      unorderedEquals(['a.txt', 'sub']),
    );
  });

  test('lists all descendants with / separators when recursive', () async {
    final entries = await platform.listEntries(location(), recursive: true);

    expect(
      entries.map((e) => e.relativePath),
      unorderedEquals(['a.txt', 'sub', 'sub/b.txt', 'sub/nested']),
    );
  });

  test('reports entry metadata', () async {
    final entries = await platform.listEntries(location(), recursive: true);
    final byPath = {for (final entry in entries) entry.relativePath: entry};

    final file = byPath['sub/b.txt']!;
    expect(file.name, 'b.txt');
    expect(file.isDirectory, isFalse);
    expect(file.size, 5);
    expect(file.lastModified, isNotNull);
    expect(file.uri!.toFilePath(), p.join(root.path, 'sub', 'b.txt'));

    final directory = byPath['sub']!;
    expect(directory.name, 'sub');
    expect(directory.isDirectory, isTrue);
    expect(directory.size, isNull);
  });

  if (testSymlinks) {
    test('does not descend into symlinked directories', () async {
      final outside = await Directory.systemTemp.createTemp('dir_picker_out');
      addTearDown(() => outside.delete(recursive: true));
      await File(p.join(outside.path, 'inside.txt')).writeAsString('');
      await Link(p.join(root.path, 'link')).create(outside.path);

      final entries = await platform.listEntries(location(), recursive: true);
      final paths = entries.map((e) => e.relativePath);

      expect(paths, contains('link'));
      expect(paths, isNot(contains('link/inside.txt')));
    });
  }

  test('rejects a location without a URI', () {
    expect(
      platform.listEntries(_NoUriLocation()),
      throwsA(isA<ArgumentError>()),
    );
  });
}

class _NoUriLocation extends PickedLocation {
  @override
  Uri? get uri => null;
}
