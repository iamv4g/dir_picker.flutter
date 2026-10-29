import 'dart:io';

import 'package:dir_picker/dir_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

/// Runs `DirPicker.persist`, `restore` and `release` through the plugin
/// registered in a real app, so the bookmark code in Swift runs on iOS and
/// macOS.
///
/// Android is not covered: it only persists SAF tree URIs, which an app
/// cannot get without the system picker.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final skip = Platform.isAndroid
      ? 'Android only persists SAF tree URIs'
      : null;
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('dir_picker_persist');
    await File(p.join(root.path, 'a.txt')).writeAsString('hi');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// The real path of [location], so `/var` and `/private/var` compare equal.
  String realPath(PickedLocation location) =>
      Directory.fromUri(location.uri!).resolveSymbolicLinksSync();

  test('a token restores the folder, which can then be listed', () async {
    final token = await DirPicker.persist(
      IOPickedLocation(Uri.directory(root.path)),
    );
    final restored = await DirPicker.restore(token);

    expect(restored, isNotNull);
    expect(realPath(restored!), root.resolveSymbolicLinksSync());
    final entries = await DirPicker.listEntries(restored);
    expect(entries.map((e) => e.name), ['a.txt']);

    await DirPicker.release(token);
  }, skip: skip);

  test('a token restores null once the folder is deleted', () async {
    final token = await DirPicker.persist(
      IOPickedLocation(Uri.directory(root.path)),
    );
    await root.delete(recursive: true);

    expect(await DirPicker.restore(token), isNull);
  }, skip: skip);

  test('an invalid token restores null', () async {
    expect(await DirPicker.restore('not a token'), isNull);
    await DirPicker.release('not a token');
  }, skip: skip);
}
