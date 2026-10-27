@TestOn('windows')
library;

import 'package:dir_picker/dir_picker.dart';
import 'package:flutter_test/flutter_test.dart';

import 'src/list_entries_contract.dart';

void main() {
  group('DirPickerWindows.listEntries', () {
    // Creating symlinks on Windows needs elevated rights or Developer Mode.
    listEntriesContract(DirPickerWindows.new);
  });
}
