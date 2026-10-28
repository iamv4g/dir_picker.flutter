@TestOn('windows')
library;

import 'dart:isolate';

import 'package:dir_picker/dir_picker.dart';
import 'package:flutter_test/flutter_test.dart';

import 'src/list_entries_contract.dart';

void main() {
  test('pick() dialog only accepts file system folders', () async {
    const fosNoChangeDir = 0x8;
    const fosPickFolders = 0x20;
    const fosForceFileSystem = 0x40;
    const fosPathMustExist = 0x800;

    // pick() also builds the dialog on a separate isolate.
    final options = await Isolate.run(DirPickerWindows.debugDialogOptions);

    for (final flag in [
      fosPickFolders,
      fosForceFileSystem,
      // Defaults that SetOptions used to drop (#17).
      fosPathMustExist,
      fosNoChangeDir,
    ]) {
      expect(
        options & flag,
        flag,
        reason:
            'options 0x${options.toRadixString(16)} lack 0x${flag.toRadixString(16)}',
      );
    }
  });

  group('DirPickerWindows.listEntries', () {
    // Creating symlinks on Windows needs elevated rights or Developer Mode.
    listEntriesContract(DirPickerWindows.new);
  });
}
