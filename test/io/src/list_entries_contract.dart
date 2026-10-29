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

  test('skips the contents of a subdirectory it cannot read', () async {
    final locked = await Directory(p.join(root.path, 'locked')).create();
    await File(p.join(locked.path, 'secret.txt')).writeAsString('');
    if (!await lockDirectory(locked)) {
      markTestSkipped(
        'Could not make a directory unreadable (running as root?)',
      );
      return;
    }
    addTearDown(() => unlockDirectory(locked));

    final entries = await platform.listEntries(location(), recursive: true);

    expect(
      entries.map((e) => e.relativePath),
      unorderedEquals(['a.txt', 'locked', 'sub', 'sub/b.txt', 'sub/nested']),
    );
  });

  if (testSymlinks) {
    test('reports a link as what it points to', () async {
      await Link(
        p.join(root.path, 'dir_link'),
      ).create(p.join(root.path, 'sub'));
      await Link(
        p.join(root.path, 'file_link'),
      ).create(p.join(root.path, 'a.txt'));
      await Link(
        p.join(root.path, 'broken_link'),
      ).create(p.join(root.path, 'gone'));

      final entries = await platform.listEntries(location());
      final byPath = {for (final entry in entries) entry.relativePath: entry};

      expect(byPath['dir_link']!.isDirectory, isTrue);
      expect(byPath['dir_link']!.size, isNull);
      expect(byPath['file_link']!.isDirectory, isFalse);
      expect(byPath['file_link']!.size, 2);
      expect(byPath['broken_link']!.isDirectory, isFalse);
      expect(byPath['broken_link']!.size, isNull);
    });

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
    expect(
      platform.streamEntries(_NoUriLocation()),
      emitsError(isA<ArgumentError>()),
    );
  });

  test('streams the same entries as listEntries', () async {
    final listed = await platform.listEntries(location(), recursive: true);
    final streamed = await platform
        .streamEntries(location(), recursive: true)
        .toList();

    expect(streamed, unorderedEquals(listed));
  });

  test('can stop after the first entry', () async {
    // Enough files that the walk would still be running after the first.
    for (var i = 0; i < 50; i++) {
      await File(p.join(root.path, 'sub', 'nested', 'f$i')).writeAsString('');
    }

    final first = await platform
        .streamEntries(location(), recursive: true)
        .first;

    expect(first.relativePath, isNotEmpty);
  });

  test('emits an error for a directory that does not exist', () {
    expect(
      platform.streamEntries(
        IOPickedLocation(Uri.directory(p.join(root.path, 'missing'))),
      ),
      emitsError(isA<FileSystemException>()),
    );
  });
}

class _NoUriLocation extends PickedLocation {
  @override
  Uri? get uri => null;
}

/// Makes [directory] unreadable for the current user. Returns `false` if it
/// is still readable afterwards, e.g. when running as root.
Future<bool> lockDirectory(Directory directory) async {
  if (Platform.isWindows) {
    await _run('icacls', [
      directory.path,
      '/deny',
      '${Platform.environment['USERNAME']}:(RX)',
    ]);
  } else {
    await _run('chmod', ['000', directory.path]);
  }
  try {
    await directory.list().drain<void>();
    return false;
  } on FileSystemException {
    return true;
  }
}

Future<void> unlockDirectory(Directory directory) async {
  if (Platform.isWindows) {
    await _run('icacls', [
      directory.path,
      '/remove:d',
      '${Platform.environment['USERNAME']}',
    ]);
  } else {
    await _run('chmod', ['755', directory.path]);
  }
}

Future<void> _run(String executable, List<String> arguments) async {
  final result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    throw ProcessException(executable, arguments, '${result.stderr}');
  }
}
