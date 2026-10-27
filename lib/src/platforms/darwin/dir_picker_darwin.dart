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

  @override
  Future<PickedLocation?> pick({PickOptions? options}) async {
    final completer = Completer<PickedLocation?>();
    final port = ReceivePort();

    port.listen((message) {
      port.close();
      try {
        completer.complete(decodePickMessage(message));
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });

    // Allocate C strings for macOS options; Swift copies them synchronously
    // before dispatching to the main queue, so freeing after the call is safe.
    final opts = options is MacosOptions ? options : const MacosOptions();
    final acceptLabelPtr = opts.acceptLabel.toNativeUtf8().cast<Char>();
    final messagePtr = opts.message.toNativeUtf8().cast<Char>();

    try {
      _bindings.pick(port.sendPort.nativePort, acceptLabelPtr, messagePtr);
    } finally {
      calloc.free(acceptLabelPtr);
      calloc.free(messagePtr);
    }

    return completer.future;
  }

  @override
  Future<List<FileSystemEntry>> listEntries(
    PickedLocation location, {
    bool recursive = false,
  }) async {
    final uri = location.uri;
    if (uri == null) {
      throw ArgumentError.value(
        location,
        'location',
        'listEntries requires a native picked location with a URI.',
      );
    }

    final completer = Completer<List<FileSystemEntry>>();
    final port = ReceivePort();

    port.listen((message) {
      port.close();
      try {
        completer.complete(decodeListEntriesMessage(message));
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });

    final uriPtr = uri.toString().toNativeUtf8().cast<Char>();
    try {
      _bindings.listEntries(port.sendPort.nativePort, uriPtr, recursive);
    } finally {
      calloc.free(uriPtr);
    }

    return completer.future;
  }
}
