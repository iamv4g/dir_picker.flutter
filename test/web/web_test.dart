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
    globalContext.delete('dirPickerTestOptions'.toJS);
    await storage
        .removeEntry(root.name, web.FileSystemRemoveOptions(recursive: true))
        .toDart;
  });

  /// Replaces `window.showDirectoryPicker` with `() => <promiseExpression>`,
  /// recording the options it's called with as JSON.
  void stubPicker(String promiseExpression) {
    globalContext['dirPickerTestRoot'] = root;
    globalContext.callMethod(
      'eval'.toJS,
      'window.showDirectoryPicker = (options) => { '
              'window.dirPickerTestOptions = JSON.stringify(options); '
              'return $promiseExpression; }'
          .toJS,
    );
  }

  String? pickerOptions() =>
      (globalContext['dirPickerTestOptions'] as JSString?)?.toDart;

  group('DirPickerWeb.pick', () {
    test('returns the picked directory handle', () async {
      stubPicker('Promise.resolve(window.dirPickerTestRoot)');

      final location = await DirPickerWeb().pick();

      expect(location, isA<WebPickedLocation>());
      location as WebPickedLocation;
      expect(location.name, root.name);
      expect(location.uri, isNull);
    });

    test('asks for read access by default', () async {
      stubPicker('Promise.resolve(window.dirPickerTestRoot)');

      await DirPickerWeb().pick();

      expect(pickerOptions(), '{"mode":"read"}');
    });

    test('passes the web options to showDirectoryPicker', () async {
      stubPicker('Promise.resolve(window.dirPickerTestRoot)');

      await DirPickerWeb().pick(
        options: const PickOptions.web(
          mode: WebPermissionMode.readwrite,
          id: 'exports',
          startIn: WebStartIn.documents,
        ),
      );

      expect(
        pickerOptions(),
        '{"mode":"readwrite","id":"exports","startIn":"documents"}',
      );
    });

    test('starts in the initial directory handle', () async {
      stubPicker('Promise.resolve(window.dirPickerTestRoot)');
      globalContext.callMethod(
        'eval'.toJS,
        'const stub = window.showDirectoryPicker; '
                'window.showDirectoryPicker = (options) => { '
                'window.dirPickerTestStartsInRoot = '
                'options.startIn === window.dirPickerTestRoot; '
                'return stub(options); }'
            .toJS,
      );

      await DirPickerWeb().pick(
        options: const PickOptions.web(startIn: WebStartIn.desktop),
        initialDirectory: WebPickedLocation(root),
      );

      expect(
        (globalContext['dirPickerTestStartsInRoot'] as JSBoolean).toDart,
        isTrue,
      );
      globalContext.delete('dirPickerTestStartsInRoot'.toJS);
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
    // Listing only needs the handle, so it must work in browsers without
    // showDirectoryPicker, such as Firefox and Safari (#23).
    setUp(() => globalContext.delete('showDirectoryPicker'.toJS));

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
