import 'dart:io';

import 'package:dir_picker/dir_picker.dart';
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

  test('throws for a directory that does not exist', () async {
    for (final recursive in [false, true]) {
      await expectLater(
        DirPicker.listEntries(location('missing'), recursive: recursive),
        throwsA(isA<Exception>()),
        reason: 'recursive: $recursive',
      );
    }
  });
}
