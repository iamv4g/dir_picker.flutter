@TestOn('posix')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dbus/dbus.dart';

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
        ['zenity', '--file-selection', '--directory', '--title=Import'],
      ]);
    });

    test('stops at zenity when the user cancels it', () async {
      final location = await picker(
        tools: {'zenity': cancelled(), 'kdialog': selected('/ignored')},
      ).pick();

      expect(location, isNull);
      expect(runs.map((run) => run.first), ['zenity']);
    });

    test('throws when zenity fails instead of reading it as cancel', () async {
      await expectLater(
        picker(
          tools: {
            'zenity': ProcessResult(0, 5, '', 'Timed out\n'),
            'kdialog': selected('/ignored'),
          },
        ).pick(),
        throwsA(
          isA<Exception>().having(
            (e) => '$e',
            'message',
            contains('PICKER_ERROR: zenity exited with code 5: Timed out'),
          ),
        ),
      );
      expect(runs.map((run) => run.first), ['zenity']);
    });

    test('throws when kdialog fails instead of reading it as cancel', () async {
      await expectLater(
        picker(tools: {'kdialog': ProcessResult(0, 254, '', '')}).pick(),
        throwsA(
          isA<Exception>().having(
            (e) => '$e',
            'message',
            contains('PICKER_ERROR: kdialog exited with code 254'),
          ),
        ),
      );
    });

    test('opens zenity and kdialog in the initial directory', () async {
      final initial = IOPickedLocation(Uri.directory('/home/user/Projects'));

      await picker(
        tools: {'zenity': cancelled()},
      ).pick(initialDirectory: initial);
      expect(runs.single, contains('--filename=/home/user/Projects/'));

      runs.clear();
      await picker(
        tools: {'kdialog': cancelled()},
      ).pick(initialDirectory: initial);
      expect(runs.last.last, '/home/user/Projects/');
    });

    test('ignores an initial directory that is not a file URI', () async {
      await picker(tools: {'zenity': cancelled()}).pick(
        initialDirectory: IOPickedLocation(
          Uri.parse('content://com.example/tree/1'),
        ),
      );
      expect(runs.single.where((arg) => arg.startsWith('--filename')), isEmpty);
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

  group(
    'DirPickerLinux.pick through the portal',
    () {
      late DBusServer server;
      late DBusAddress address;
      late DBusClient portalClient;
      late _FakePortal portal;
      late List<String> runs;

      setUp(() async {
        server = DBusServer();
        address = await server.listenAddress(
          DBusAddress.unix(dir: Directory.systemTemp),
        );
        portalClient = DBusClient(address);
        await portalClient.requestName('org.freedesktop.portal.Desktop');
        portal = _FakePortal();
        await portalClient.registerObject(portal);
        runs = [];
      });

      tearDown(() async {
        await portalClient.close();
        await server.close();
      });

      Future<PickedLocation?> pick({int? appWindow}) =>
          DirPickerLinux.withBackends(
            sessionBus: () => DBusClient(address),
            appWindow: () => appWindow,
            runProcess: (executable, arguments) async {
              runs.add(executable);
              throw ProcessException(executable, arguments, 'not found', 2);
            },
          ).pick().timeout(const Duration(seconds: 5));

      test('returns the picked folder', () async {
        portal.response = 0;
        expect((await pick())?.uri, Uri.directory('/tmp/picked'));
        expect(runs, isEmpty);
      });

      test('passes the app window as the X11 parent window', () async {
        portal.response = 0;
        await pick(appWindow: 0x3a00007);
        expect(portal.parentWindow, 'x11:3a00007');
      });

      test('passes the initial directory as current_folder', () async {
        portal.response = 0;

        await DirPickerLinux.withBackends(
          sessionBus: () => DBusClient(address),

          appWindow: () => null,
        ).pick(
          initialDirectory: IOPickedLocation(Uri.directory('/home/user/ä')),
        );

        expect(portal.currentFolder, [...utf8.encode('/home/user/ä/'), 0]);
      });

      test('passes no parent window when the app window is unknown', () async {
        portal.response = 0;
        await pick();
        expect(portal.parentWindow, '');
      });

      test('receives a Response sent before the OpenFile reply', () async {
        portal
          ..response = 0
          ..respondBeforeReply = true;
        expect((await pick())?.uri, Uri.directory('/tmp/picked'));
      });

      test(
        'receives a Response on a handle other than the predicted one',
        () async {
          // Portals older than 0.9 ignore handle_token.
          portal
            ..response = 0
            ..legacyHandle = true;
          expect((await pick())?.uri, Uri.directory('/tmp/picked'));
        },
      );

      test('returns null when the user cancels', () async {
        portal.response = 1;
        expect(await pick(), isNull);
        expect(runs, isEmpty);
      });

      test('returns null when the dialog is closed (response 2)', () async {
        // The GTK backend sends 2 for Esc or the window's close button.
        portal.response = 2;
        expect(await pick(), isNull);
        expect(runs, isEmpty);
      });
    },
    skip: Platform.isLinux ? false : 'package:dbus only authenticates on Linux',
  );

  group('DirPickerLinux.listEntries', () {
    listEntriesContract(DirPickerLinux.new, testSymlinks: true);
  });
}

/// A fake `org.freedesktop.portal.FileChooser`. It replies to `OpenFile` with
/// the request handle and sends `Response` on it, by default shortly after the
/// reply.
class _FakePortal extends DBusObject {
  _FakePortal() : super(DBusObjectPath('/org/freedesktop/portal/desktop'));

  int response = 0;
  bool respondBeforeReply = false;
  String? parentWindow;
  List<int>? currentFolder;
  bool legacyHandle = false;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface != 'org.freedesktop.portal.FileChooser' ||
        call.name != 'OpenFile') {
      return DBusMethodErrorResponse.unknownMethod();
    }
    parentWindow = call.values[0].asString();
    currentFolder = call.values[2]
        .asStringVariantDict()['current_folder']
        ?.asByteArray()
        .toList();
    final token = call.values[2]
        .asStringVariantDict()['handle_token']!
        .asString();
    final sender = call.sender!.substring(1).replaceAll('.', '_');
    final handle = DBusObjectPath(
      legacyHandle
          ? '/org/freedesktop/portal/desktop/request/legacy/1'
          : '/org/freedesktop/portal/desktop/request/$sender/$token',
    );

    Future<void> respond() => client!.emitSignal(
      path: handle,
      interface: 'org.freedesktop.portal.Request',
      name: 'Response',
      values: [
        DBusUint32(response),
        DBusDict.stringVariant({
          if (response == 0) 'uris': DBusArray.string(['file:///tmp/picked']),
        }),
      ],
    );

    if (respondBeforeReply) {
      await respond();
    } else {
      Timer(const Duration(milliseconds: 100), respond);
    }
    return DBusMethodSuccessResponse([handle]);
  }
}
