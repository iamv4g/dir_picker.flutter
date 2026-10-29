// ignore_for_file: avoid_print

import 'dart:io';

import 'package:ffigen/ffigen.dart';

/// Generates FFI bindings for Darwin (iOS/macOS) native classes.
///
/// Run with:
///   dart run tool/ffigen.dart
void main() {
  final packageRoot = Platform.script.resolve('../');

  print('Generating Darwin bindings...');
  final headerUri = packageRoot.resolve(
    'darwin/dir_picker/Sources/dir_picker/include/dir_picker_ffi.h',
  );

  FfiGenerator(
    // 1. Output configuration
    output: Output(
      dartFile: packageRoot.resolve(
        'lib/src/platforms/darwin/native_bindings.g.dart',
      ),
      style: const DynamicLibraryBindings(
        wrapperName: 'DirPickerBindings',
        wrapperDocComment: 'Bindings for Darwin (iOS/macOS) dir_picker_ffi.h.',
      ),
      commentType: CommentType(CommentStyle.any, CommentLength.full),
    ),

    // 2. Header configuration
    headers: Headers(
      entryPoints: [headerUri],
      include: (uri) => uri == headerUri,
    ),

    // 3. Declaration filters
    functions: Functions(
      include: Declarations.includeSet({
        'dir_picker_cancel_entries',
        'dir_picker_init_dart_api_dl',
        'dir_picker_persist',
        'dir_picker_pick',
        'dir_picker_release',
        'dir_picker_restore',
        'dir_picker_stream_entries',
      }),
      rename: (decl) {
        final stripped = decl.originalName.replaceFirst('dir_picker_', '');
        return stripped.replaceAllMapped(
          RegExp(r'_([a-z])'),
          (m) => m.group(1)!.toUpperCase(),
        );
      },
    ),
  ).generate();

  print('Generated Darwin bindings successfully.');
}
