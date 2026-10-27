@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:dir_picker/dir_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

// Uses the origin private file system, which hands out real
// FileSystemDirectoryHandles without a picker dialog.
void main() {
  late web.FileSystemDirectoryHandle storage;
  late web.FileSystemDirectoryHandle root;
  late bool hadPicker;
  JSAny? originalPicker;

  setUp(() async {
    storage = await web.window.navigator.storage.getDirectory().toDart;
    root = await storage
        .getDirectoryHandle(
          'dir_picker_test_${DateTime.now().microsecondsSinceEpoch}',
          web.FileSystemGetDirectoryOptions(create: true),
        )
        .toDart;
    await _writeFile(root, 'a.txt', 'hi');
    final sub = await root
        .getDirectoryHandle(
          'sub',
          web.FileSystemGetDirectoryOptions(create: true),
        )
        .toDart;
    await _writeFile(sub, 'b.txt', 'hello');

    hadPicker = globalContext.has('showDirectoryPicker');
    originalPicker = globalContext['showDirectoryPicker'];
  });

  tearDown(() async {
    if (hadPicker) {
      globalContext['showDirectoryPicker'] = originalPicker;
    } else {
      globalContext.delete('showDirectoryPicker'.toJS);
    }
    globalContext.delete('dirPickerTestRoot'.toJS);
    await storage
        .removeEntry(root.name, web.FileSystemRemoveOptions(recursive: true))
        .toDart;
  });

  /// Replaces `window.showDirectoryPicker` with `() => <promiseExpression>`.
  void stubPicker(String promiseExpression) {
    globalContext['dirPickerTestRoot'] = root;
    globalContext.callMethod(
      'eval'.toJS,
      'window.showDirectoryPicker = () => $promiseExpression'.toJS,
    );
  }

  group('DirPickerWeb.pick', () {
    test('returns the picked directory handle', () async {
      stubPicker('Promise.resolve(window.dirPickerTestRoot)');

      final location = await DirPickerWeb().pick();

      expect(location, isA<WebPickedLocation>());
      location as WebPickedLocation;
      expect(location.name, root.name);
      expect(location.uri, isNull);
    });

    test('returns null when the user cancels', () async {
      stubPicker(
        "Promise.reject(new DOMException('The user aborted a request.', "
        "'AbortError'))",
      );

      expect(await DirPickerWeb().pick(), isNull);
    });

    test('rethrows other errors', () async {
      stubPicker(
        "Promise.reject(new DOMException('Not allowed.', 'SecurityError'))",
      );

      await expectLater(DirPickerWeb().pick(), throwsA(anything));
    });

    test('throws UnsupportedError without the File System Access API', () {
      globalContext.delete('showDirectoryPicker'.toJS);

      expect(DirPickerWeb().pick(), throwsUnsupportedError);
    });
  });

  group('DirPickerWeb.listEntries', () {
    setUp(() => stubPicker('Promise.reject()'));

    test('lists only immediate children by default', () async {
      final entries = await DirPickerWeb().listEntries(WebPickedLocation(root));

      expect(
        entries.map((e) => e.relativePath),
        unorderedEquals(['a.txt', 'sub']),
      );
    });

    test('lists all descendants and their metadata when recursive', () async {
      final entries = await DirPickerWeb().listEntries(
        WebPickedLocation(root),
        recursive: true,
      );
      final byPath = {for (final entry in entries) entry.relativePath: entry};

      expect(byPath.keys, unorderedEquals(['a.txt', 'sub', 'sub/b.txt']));
      final file = byPath['sub/b.txt']!;
      expect(file.name, 'b.txt');
      expect(file.isDirectory, isFalse);
      expect(file.size, 5);
      expect(file.lastModified, isNotNull);
      expect(file.uri, isNull);
      final directory = byPath['sub']!;
      expect(directory.isDirectory, isTrue);
      expect(directory.size, isNull);
    });

    test('rejects a non-web location', () {
      expect(
        DirPickerWeb().listEntries(IOPickedLocation(Uri.directory('/tmp'))),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

Future<void> _writeFile(
  web.FileSystemDirectoryHandle directory,
  String name,
  String contents,
) async {
  final file = await directory
      .getFileHandle(name, web.FileSystemGetFileOptions(create: true))
      .toDart;
  final writable = await file.createWritable().toDart;
  await writable.write(contents.toJS).toDart;
  await writable.close().toDart;
}
