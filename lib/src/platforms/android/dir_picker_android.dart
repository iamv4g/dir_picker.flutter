import 'dart:async';

import 'package:jni/jni.dart';

import '../../location/file_system_entry.dart';
import '../../location/picked_location.dart';
import '../../options/pick_options.dart';
import '../../platform_interface/dir_picker_platform.dart';
import '../entries_json.dart';
import 'native_bindings.g.dart' as native;

/// DirPicker implementation for Android.
///
/// Uses JNI via the jni package. [PickerCallback.implement()] is backed by
/// a RawReceivePort (native port) internally — no manual port management needed.
class DirPickerAndroid extends DirPickerPlatform {
  static void registerWith() {
    DirPickerPlatform.instance = DirPickerAndroid();
  }

  @override
  Future<PickedLocation?> pick({
    PickOptions? options,
    PickedLocation? initialDirectory,
  }) {
    final androidOptions = options is AndroidOptions
        ? options
        : AndroidOptions();
    final completer = Completer<PickedLocation?>();

    final callback = native.PickerCallback.implement(
      native.$PickerCallback(
        onSuccess: (jUri) {
          final uri = Uri.parse(jUri.toDartString());
          jUri.release();
          completer.complete(IOPickedLocation(uri));
        },
        onCancelled: () => completer.complete(null),
        onError: (jCode, jMessage) {
          final code = jCode.toDartString();
          final msg = jMessage.toDartString();
          jCode.release();
          jMessage.release();
          completer.completeError(Exception('$code: $msg'));
        },
      ),
    );

    // Only a content:// location from an earlier pick can be opened.
    final initialUri = switch (initialDirectory?.uri) {
      final uri? when uri.scheme == 'content' => uri.toString().toJString(),
      _ => null,
    };

    // Non-blocking: Kotlin launches coroutine internally
    try {
      native.DirPicker.pick(androidOptions.shouldPersist, initialUri, callback);
    } finally {
      initialUri?.release();
    }

    return completer.future.whenComplete(() => callback.release());
  }

  @override
  Future<List<FileSystemEntry>> listEntries(
    PickedLocation location, {
    bool recursive = false,
  }) {
    final uri = location.uri;
    if (uri == null) {
      throw ArgumentError.value(
        location,
        'location',
        'listEntries requires a native picked location with a URI.',
      );
    }

    final completer = Completer<List<FileSystemEntry>>();
    final callback = native.ListEntriesCallback.implement(
      native.$ListEntriesCallback(
        onSuccess: (jJson) {
          final json = jJson.toDartString();
          jJson.release();
          try {
            completer.complete(decodeEntriesJson(json));
          } catch (error, stackTrace) {
            completer.completeError(error, stackTrace);
          }
        },
        onError: (jCode, jMessage) {
          final code = jCode.toDartString();
          final message = jMessage.toDartString();
          jCode.release();
          jMessage.release();
          completer.completeError(Exception('$code: $message'));
        },
      ),
    );

    final treeUri = uri.toString().toJString();
    try {
      native.DirPicker.listEntries(treeUri, recursive, callback);
    } finally {
      treeUri.release();
    }

    return completer.future.whenComplete(() => callback.release());
  }
}
