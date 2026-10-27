// ignore_for_file: avoid_print

import 'dart:io';

import 'package:jnigen/jnigen.dart';

/// Generates JNI bindings for the Android native classes.
///
/// Run with:
///   dart run tool/jnigen.dart
void main(List<String> args) async {
  final packageRoot = Platform.script.resolve('../');

  // Step 1 — Compile plugin Kotlin classes first. This avoids a bootstrap
  // issue where Flutter's Dart build may reference bindings that are about to
  // be regenerated.
  print('Running Gradle dir_picker:compileDebugKotlin in example/android/...');

  final result = await Process.run(
    './gradlew',
    ['dir_picker:compileDebugKotlin'],
    workingDirectory: packageRoot.resolve('example/android/').toFilePath(),
    runInShell: true,
  );

  stdout.write(result.stdout);
  stderr.write(result.stderr);

  if (result.exitCode != 0) {
    throw Exception('Gradle dir_picker:compileDebugKotlin failed');
  }

  // Step 2 — Generate JNI bindings
  print('Generating JNI bindings...');
  final bindingsUri = packageRoot.resolve(
    'lib/src/platforms/android/native_bindings.g.dart',
  );
  await generateJniBindings(
    Config(
      outputConfig: OutputConfig(
        dartConfig: DartCodeOutputConfig(
          path: bindingsUri,
          structure: OutputStructure.singleFile,
        ),
      ),
      sourcePath: [
        packageRoot.resolve('android/src/main/kotlin/com/vanvixi/dir_picker/'),
      ],
      classPath: [
        packageRoot.resolve(
          'example/build/dir_picker/tmp/kotlin-classes/debug',
        ),
      ],
      classes: [
        'com.vanvixi.dir_picker.DirPicker',
        'com.vanvixi.dir_picker.ListEntriesCallback',
        'com.vanvixi.dir_picker.PickerCallback',
      ],
    ),
  );

  // Step 3 — Silence lints that JNIgen's own ignore list misses, so the
  // generated file doesn't cost pub.dev static analysis points.
  _addIgnoreForFile(File.fromUri(bindingsUri), _extraIgnoredLints);

  print('JNI bindings generated successfully.');
}

const _extraIgnoredLints = ['prefer_initializing_formals'];

/// Inserts `// ignore_for_file: <lint>` after the last existing ignore line.
void _addIgnoreForFile(File file, List<String> lints) {
  final lines = file.readAsLinesSync();
  final lastIgnore = lines.lastIndexWhere(
    (line) => line.startsWith('// ignore_for_file:'),
  );
  final missing = lints
      .map((lint) => '// ignore_for_file: $lint')
      .where((line) => !lines.contains(line));
  lines.insertAll(lastIgnore + 1, missing);
  file.writeAsStringSync('${lines.join('\n')}\n');
}
