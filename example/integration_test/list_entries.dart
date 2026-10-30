import 'dart:ffi';
import 'dart:io';

import 'package:dir_picker/dir_picker.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

/// Runs `DirPicker.listEntries` through the plugin registered in a real app,
/// against a real directory tree, so the native bridges (Swift FFI on
/// iOS/macOS) are exercised end to end.
///
/// `pick()` needs a user, so it is not covered. Android is not covered either:
/// its `listEntries` only accepts SAF tree URIs, which an app cannot get
/// without the system picker.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  /// Builds this tree in a temp directory:
  /// ```
  /// a.txt              (2 bytes)
  /// sub/
  ///   b.txt            (5 bytes)
  ///   nested/
  /// tài liệu/
  ///   ghi chú 1.txt    (3 bytes)
  /// ```
  setUp(() async {
    root = await Directory.systemTemp.createTemp('dir_picker_it');
    await File(p.join(root.path, 'a.txt')).writeAsString('hi');
    await Directory(p.join(root.path, 'sub', 'nested')).create(recursive: true);
    await File(p.join(root.path, 'sub', 'b.txt')).writeAsString('hello');
    await Directory(p.join(root.path, 'tài liệu')).create();
    await File(
      p.join(root.path, 'tài liệu', 'ghi chú 1.txt'),
    ).writeAsString('abc');
  });

  tearDown(() => root.delete(recursive: true));

  IOPickedLocation location([String path = '']) =>
      IOPickedLocation(Uri.directory(p.join(root.path, path)));

  test('registers the implementation for this platform', () {
    final expected = switch (Platform.operatingSystem) {
      'ios' || 'macos' => DirPickerDarwin,
      'linux' => DirPickerLinux,
      'windows' => DirPickerWindows,
      'android' => DirPickerAndroid,
      final os => throw UnsupportedError('Unexpected platform: $os'),
    };

    expect(DirPickerPlatform.instance.runtimeType, expected);
  });

  test('lists only immediate children by default', () async {
    final entries = await DirPicker.listEntries(location());

    expect(
      entries.map((e) => e.relativePath),
      unorderedEquals(['a.txt', 'sub', 'tài liệu']),
    );
  });

  test('lists all descendants with / separators when recursive', () async {
    final entries = await DirPicker.listEntries(location(), recursive: true);

    expect(
      entries.map((e) => e.relativePath),
      unorderedEquals([
        'a.txt',
        'sub',
        'sub/b.txt',
        'sub/nested',
        'tài liệu',
        'tài liệu/ghi chú 1.txt',
      ]),
    );
  });

  test('reports entry metadata', () async {
    final entries = await DirPicker.listEntries(location(), recursive: true);
    final byPath = {for (final entry in entries) entry.relativePath: entry};

    final file = byPath['sub/b.txt']!;
    expect(file.name, 'b.txt');
    expect(file.isDirectory, isFalse);
    expect(file.size, 5);
    expect(
      file.lastModified!.difference(DateTime.now()).abs(),
      lessThan(const Duration(hours: 1)),
    );
    expect(
      File.fromUri(file.uri!).resolveSymbolicLinksSync(),
      File(p.join(root.path, 'sub', 'b.txt')).resolveSymbolicLinksSync(),
    );

    final directory = byPath['sub']!;
    expect(directory.name, 'sub');
    expect(directory.isDirectory, isTrue);
    expect(directory.size, isNull);
  });

  test('keeps spaces and non-ASCII characters in names', () async {
    final entries = await DirPicker.listEntries(
      location('tài liệu'),
      recursive: true,
    );

    expect(entries, hasLength(1));
    expect(entries.single.name, 'ghi chú 1.txt');
    expect(entries.single.relativePath, 'ghi chú 1.txt');
    expect(entries.single.size, 3);
    expect(File.fromUri(entries.single.uri!).readAsStringSync(), 'abc');
  });

  test('lists an empty directory as empty', () async {
    expect(await DirPicker.listEntries(location('sub/nested')), isEmpty);
    expect(
      await DirPicker.listEntries(location('sub/nested'), recursive: true),
      isEmpty,
    );
  });

  test(
    'reports a link as what it points to, without listing its contents',
    () async {
      try {
        await Link(
          p.join(root.path, 'dir_link'),
        ).create(p.join(root.path, 'sub'));
        await Link(
          p.join(root.path, 'file_link'),
        ).create(p.join(root.path, 'a.txt'));
        await Link(
          p.join(root.path, 'broken_link'),
        ).create(p.join(root.path, 'gone'));
      } on FileSystemException catch (e) {
        markTestSkipped('Cannot create links here: $e');
        return;
      }

      final entries = await DirPicker.listEntries(location(), recursive: true);
      final byPath = {for (final entry in entries) entry.relativePath: entry};

      expect(byPath['dir_link']!.isDirectory, isTrue);
      expect(byPath['dir_link']!.size, isNull);
      expect(byPath['file_link']!.isDirectory, isFalse);
      expect(byPath['file_link']!.size, 2);
      expect(byPath['broken_link']!.isDirectory, isFalse);
      expect(byPath['broken_link']!.size, isNull);
      expect(
        byPath.keys.where((path) => path.startsWith('dir_link/')),
        isEmpty,
      );
    },
  );

  test('skips the contents of a subdirectory it cannot read', () async {
    final locked = await Directory(p.join(root.path, 'locked')).create();
    await File(p.join(locked.path, 'secret.txt')).writeAsString('');
    await _setReadable(locked, false);
    addTearDown(() => _setReadable(locked, true));
    if (await _isReadable(locked)) {
      markTestSkipped('Could not make a directory unreadable');
      return;
    }

    final entries = await DirPicker.listEntries(location(), recursive: true);

    expect(
      entries.map((e) => e.relativePath),
      unorderedEquals([
        'a.txt',
        'locked',
        'sub',
        'sub/b.txt',
        'sub/nested',
        'tài liệu',
        'tài liệu/ghi chú 1.txt',
      ]),
    );
  });

  test('throws for a directory that does not exist', () async {
    for (final recursive in [false, true]) {
      await expectLater(
        DirPicker.listEntries(location('missing'), recursive: recursive),
        throwsA(isA<Exception>()),
        reason: 'recursive: $recursive',
      );
    }
  });

  group('streamEntries', () {
    /// Adds [count] files to `many/`, more than one native batch (200).
    Future<void> addFiles(int count) async {
      final many = await Directory(p.join(root.path, 'many')).create();
      for (var i = 0; i < count; i++) {
        await File(p.join(many.path, 'f$i.txt')).writeAsString('$i');
      }
    }

    test(
      'streams the same entries as listEntries, over several batches',
      () async {
        await addFiles(450);

        final listed = await DirPicker.listEntries(location(), recursive: true);
        final streamed = await DirPicker.streamEntries(
          location(),
          recursive: true,
        ).toList();

        expect(listed, hasLength(6 + 1 + 450));
        expect(streamed, unorderedEquals(listed));
      },
    );

    test('stops early, and the next walk still works', () async {
      await addFiles(450);

      final firstFive = await DirPicker.streamEntries(
        location(),
        recursive: true,
      ).take(5).toList();
      expect(firstFive, hasLength(5));

      final all = await DirPicker.streamEntries(
        location(),
        recursive: true,
      ).toList();
      expect(all, hasLength(6 + 1 + 450));
    });

    test('emits an error for a directory that does not exist', () async {
      await expectLater(
        DirPicker.streamEntries(location('missing')),
        emitsError(isA<Exception>()),
      );
    });
  });
}

Future<bool> _isReadable(Directory directory) async {
  try {
    await directory.list().drain<void>();
    return true;
  } on FileSystemException {
    return false;
  }
}

/// Denies or restores read access to [directory] for the current user.
/// Uses icacls on Windows and chmod(2) elsewhere, since iOS apps can't run
/// processes.
Future<void> _setReadable(Directory directory, bool readable) async {
  if (Platform.isWindows) {
    final user = Platform.environment['USERNAME']!;
    final result = await Process.run('icacls', [
      directory.path,
      ...readable ? ['/remove:d', user] : ['/deny', '$user:(RX)'],
    ]);
    if (result.exitCode != 0) throw Exception('icacls: ${result.stderr}');
    return;
  }

  final path = directory.path.toNativeUtf8();
  try {
    if (_chmod(path, readable ? 493 /* 0755 */ : 0) != 0) {
      throw Exception('chmod ${directory.path} failed');
    }
  } finally {
    calloc.free(path);
  }
}

// mode_t is 16 bits on Darwin and 32 bits on Linux; both are passed in a
// full register.
final _chmod = DynamicLibrary.process()
    .lookupFunction<
      Int32 Function(Pointer<Utf8>, Uint32),
      int Function(Pointer<Utf8>, int)
    >('chmod');
