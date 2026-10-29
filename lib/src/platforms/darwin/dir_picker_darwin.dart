import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../../location/file_system_entry.dart';
import '../../location/picked_location.dart';
import '../../options/pick_options.dart';
import '../../platform_interface/dir_picker_platform.dart';
import 'native_bindings.g.dart' as native;
import 'port_message.dart';

/// DirPicker implementation for Apple platforms (iOS and macOS).
///
/// Uses FFI with DartApiDl NativePort for async directory picking.
class DirPickerDarwin extends DirPickerPlatform {
  DirPickerDarwin() {
    final dylib = DynamicLibrary.process();
    _bindings = native.DirPickerBindings(dylib);

    final result = _bindings.initDartApiDl(NativeApi.initializeApiDLData);
    if (result != 0) {
      throw StateError('Failed to initialize Dart API DL (code: $result)');
    }
  }

  static void registerWith() {
    DirPickerPlatform.instance = DirPickerDarwin();
  }

  late final native.DirPickerBindings _bindings;

  /// Calls [send] with a new port, and completes with [decode] of the one
  /// message the native side posts back.
  Future<T> _request<T>(
    void Function(int nativePort) send,
    T Function(Object? message) decode,
  ) {
    final completer = Completer<T>();
    final port = ReceivePort();

    port.listen((message) {
      port.close();
      try {
        completer.complete(decode(message));
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });

    try {
      send(port.sendPort.nativePort);
    } catch (_) {
      port.close();
      rethrow;
    }
    return completer.future;
  }

  /// Calls [send] with [value] as a C string, freed when it returns. Swift
  /// copies it synchronously.
  static void _withCString(String value, void Function(Pointer<Char>) send) {
    final pointer = value.toNativeUtf8().cast<Char>();
    try {
      send(pointer);
    } finally {
      calloc.free(pointer);
    }
  }

  @override
  Future<PickedLocation?> pick({
    PickOptions? options,
    PickedLocation? initialDirectory,
  }) async {
    // Allocate C strings for macOS options; Swift copies them synchronously
    // before dispatching to the main queue, so freeing after the call is safe.
    final opts = options is MacosOptions ? options : const MacosOptions();
    final acceptLabelPtr = opts.acceptLabel.toNativeUtf8().cast<Char>();
    final messagePtr = opts.message.toNativeUtf8().cast<Char>();
    final initialDirectoryPtr = switch (initialDirectory?.uri) {
      final uri? when uri.scheme == 'file' =>
        uri.toString().toNativeUtf8().cast<Char>(),
      _ => nullptr.cast<Char>(),
    };

    return _request((port) {
      try {
        _bindings.pick(port, acceptLabelPtr, messagePtr, initialDirectoryPtr);
      } finally {
        calloc.free(acceptLabelPtr);
        calloc.free(messagePtr);
        if (initialDirectoryPtr != nullptr) calloc.free(initialDirectoryPtr);
      }
    }, decodePickMessage);
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
    late final ReceivePort port;
    var isDone = false;

    void finish([Object? error, StackTrace? stackTrace]) {
      isDone = true;
      port.close();
      if (error != null) controller.addError(error, stackTrace);
      controller.close();
    }

    controller = StreamController(
      onListen: () {
        port = ReceivePort();
        port.listen((message) {
          final List<FileSystemEntry>? batch;
          try {
            batch = decodeEntriesStreamMessage(message);
          } catch (error, stackTrace) {
            finish(error, stackTrace);
            return;
          }
          if (batch == null) {
            finish();
          } else {
            batch.forEach(controller.add);
          }
        });
        _withCString(
          uri.toString(),
          (uriPtr) => _bindings.streamEntries(
            port.sendPort.nativePort,
            uriPtr,
            recursive,
          ),
        );
      },
      onCancel: () {
        if (isDone) return;
        // Swift stops at the next entry. Its remaining messages go to a
        // closed port and are dropped.
        _bindings.cancelEntries(port.sendPort.nativePort);
        isDone = true;
        port.close();
      },
    );
    return controller.stream;
  }

  @override
  Future<String> persist(PickedLocation location) async {
    final uri = location.uri;
    if (uri == null || uri.scheme != 'file') {
      throw ArgumentError.value(
        location,
        'location',
        'persist requires a file:// location on iOS and macOS.',
      );
    }
    return _request(
      (port) => _withCString(
        uri.toString(),
        (uriPtr) => _bindings.persist(port, uriPtr),
      ),
      decodePersistMessage,
    );
  }

  @override
  Future<PickedLocation?> restore(String token) => _request(
    (port) =>
        _withCString(token, (tokenPtr) => _bindings.restore(port, tokenPtr)),
    decodePickMessage,
  );

  @override
  Future<void> release(String token) => _request(
    (port) =>
        _withCString(token, (tokenPtr) => _bindings.release(port, tokenPtr)),
    decodeReleaseMessage,
  );
}
