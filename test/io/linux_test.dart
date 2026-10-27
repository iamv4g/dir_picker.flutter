@TestOn('posix')
library;

import 'dart:io';

import 'package:dir_picker/dir_picker.dart';
import 'package:flutter_test/flutter_test.dart';

import 'src/list_entries_contract.dart';

void main() {
  group('DirPickerLinux.pick', () {
    late List<List<String>> runs;

    setUp(() => runs = []);

    /// [tools] maps an executable to its result. Missing tools throw a
    /// [ProcessException], as [Process.run] does.
    DirPickerLinux picker({
      Future<Uri?> Function(LinuxOptions options)? portal,
      Map<String, ProcessResult> tools = const {},
    }) {
      return DirPickerLinux.withBackends(
        portalPicker: portal ?? (_) async => throw Exception('no portal'),
        runProcess: (executable, arguments) async {
          runs.add([executable, ...arguments]);
          final result = tools[executable];
          if (result == null) {
            throw ProcessException(executable, arguments, 'not found', 2);
          }
          return result;
        },
      );
    }

    ProcessResult selected(String path) => ProcessResult(0, 0, '$path\n', '');
    ProcessResult cancelled() => ProcessResult(0, 1, '', '');

    test('uses the portal result without running fallbacks', () async {
      LinuxOptions? received;
      final location = await picker(
        portal: (options) async {
          received = options;
          return Uri.directory('/home/user/Projects');
        },
        tools: {'zenity': selected('/ignored')},
      ).pick(options: const LinuxOptions(title: 'Import'));

      expect(location?.uri, Uri.directory('/home/user/Projects'));
      expect(received?.title, 'Import');
      expect(runs, isEmpty);
    });

    test('treats a cancelled portal dialog as cancelled', () async {
      final location = await picker(
        portal: (_) async => null,
        tools: {'zenity': selected('/ignored')},
      ).pick();

      expect(location, isNull);
      expect(runs, isEmpty);
    });

    test('falls back to zenity when the portal is unavailable', () async {
      final location =
          await picker(tools: {'zenity': selected('/home/user/Projects')}).pick(
            options: const LinuxOptions(title: 'Import', acceptLabel: 'Use'),
          );

      expect(location?.uri, Uri.directory('/home/user/Projects'));
      expect(runs, [
        [
          'zenity',
          '--file-selection',
          '--directory',
          '--title=Import',
          '--ok-label=Use',
        ],
      ]);
    });

    test('stops at zenity when the user cancels it', () async {
      final location = await picker(
        tools: {'zenity': cancelled(), 'kdialog': selected('/ignored')},
      ).pick();

      expect(location, isNull);
      expect(runs.map((run) => run.first), ['zenity']);
    });

    test('falls back to kdialog when zenity is missing', () async {
      final location = await picker(
        tools: {'kdialog': selected('/home/user/Projects')},
      ).pick(options: const LinuxOptions(title: 'Import'));

      expect(location?.uri, Uri.directory('/home/user/Projects'));
      expect(runs.map((run) => run.first), ['zenity', 'kdialog']);
      expect(runs.last.sublist(1, 4), [
        '--title',
        'Import',
        '--getexistingdirectory',
      ]);
    });

    test('throws UnsupportedError when no picker is available', () async {
      await expectLater(picker().pick(), throwsUnsupportedError);
      expect(runs.map((run) => run.first), ['zenity', 'kdialog']);
    });

    test('ignores options meant for other platforms', () async {
      await picker(
        tools: {'zenity': cancelled()},
      ).pick(options: const PickOptions.windows(title: 'Windows only'));

      expect(runs.single, contains('--title=Select Directory'));
    });
  });

  group('DirPickerLinux.listEntries', () {
    listEntriesContract(DirPickerLinux.new, testSymlinks: true);
  });
}
