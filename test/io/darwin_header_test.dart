import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Dart gets the address of each function of the C header from the
/// Objective-C class DirPickerFFISymbols, which only knows the functions in
/// the header's DIR_PICKER_FUNCTIONS list (see darwin_symbols.dart).
void main() {
  final header = File(
    'darwin/dir_picker/Sources/dir_picker/include/dir_picker_ffi.h',
  ).readAsStringSync();

  test('DIR_PICKER_FUNCTIONS lists every function the header declares', () {
    final declared = RegExp(
      r'^\w[\w ]*?\**\s*\b(dir_picker_\w+)\(',
      multiLine: true,
    ).allMatches(header).map((m) => m[1]!).toList();
    final list = RegExp(
      r'#define DIR_PICKER_FUNCTIONS\(X\)((?:[^\n]*\\\n)*[^\n]*)',
    ).firstMatch(header);
    expect(list, isNotNull, reason: 'the header has no DIR_PICKER_FUNCTIONS');
    final listed = RegExp(r'X\((\w+)\)')
        .allMatches(list![1]!)
        .map((m) => m[1]!)
        .toList();

    expect(declared, hasLength(7));
    expect(listed, unorderedEquals(declared));
    expect(listed.toSet(), hasLength(listed.length), reason: 'duplicates');
  });
}
