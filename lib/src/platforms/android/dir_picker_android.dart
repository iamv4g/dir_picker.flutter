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
  }) => streamEntries(location, recursive: recursive).toList();

  @override
  Stream<FileSystemEntry> streamEntries(
    PickedLocation location, {
    bool recursive = false,
  }) {
    final uri = location.uri;
    if (uri == null) {
      return Stream.error(
        ArgumentError.value(
          location,
          'location',
          'listEntries requires a native picked location with a URI.',
        ),
      );
    }

    late final StreamController<FileSystemEntry> controller;
    native.EntriesStream? stream;
    native.EntriesStreamCallback? callback;
    var isCancelled = false;

    // Kotlin always ends with onDone or onError, also after a cancel, so the
    // callback and stream are released there.
    void finish([Object? error]) {
      callback?.release();
      stream?.release();
      if (isCancelled) return;
      if (error != null) controller.addError(error);
      controller.close();
    }

    controller = StreamController(
      onListen: () {
        callback = native.EntriesStreamCallback.implement(
          native.$EntriesStreamCallback(
            onBatch: (jJson) {
              final json = jJson.toDartString();
              jJson.release();
              if (isCancelled) return;
              try {
                decodeEntriesJson(json).forEach(controller.add);
              } catch (error, stackTrace) {
                controller.addError(error, stackTrace);
              }
            },
            onDone: finish,
            onError: (jCode, jMessage) {
              final code = jCode.toDartString();
              final message = jMessage.toDartString();
              jCode.release();
              jMessage.release();
              finish(Exception('$code: $message'));
            },
          ),
        );
        final treeUri = uri.toString().toJString();
        try {
          stream = native.DirPicker.streamEntries(
            treeUri,
            recursive,
            callback!,
          );
        } finally {
          treeUri.release();
        }
      },
      onCancel: () {
        if (controller.isClosed) return;
        isCancelled = true;
        stream?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<String> persist(PickedLocation location) async {
    final uri = location.uri;
    if (uri == null || uri.scheme != 'content') {
      throw ArgumentError.value(
        location,
        'location',
        'persist requires a content:// location on Android.',
      );
    }
    final token = uri.toString();
    _callWithUri(token, native.DirPicker.persist, errorCode: 'PERSIST_ERROR');
    return token;
  }

  @override
  Future<PickedLocation?> restore(String token) async {
    final uri = Uri.tryParse(token);
    if (uri == null || uri.scheme != 'content') return null;
    final isPersisted = _callWithUri(
      token,
      native.DirPicker.isPersisted,
      errorCode: 'RESTORE_ERROR',
    );
    return isPersisted ? IOPickedLocation(uri) : null;
  }

  @override
  Future<void> release(String token) async {
    _callWithUri(
      token,
      native.DirPicker.releasePersisted,
      errorCode: 'RELEASE_ERROR',
    );
  }

  /// Calls [method] with [uri] as a Java string, and turns a Java exception
  /// into an `Exception('$errorCode: …')`.
  static T _callWithUri<T>(
    String uri,
    T Function(JString uri) method, {
    required String errorCode,
  }) {
    final jUri = uri.toJString();
    try {
      return method(jUri);
    } on JThrowable catch (e) {
      final message = e.message;
      e.release();
      throw Exception('$errorCode: $message');
    } finally {
      jUri.release();
    }
  }
}
