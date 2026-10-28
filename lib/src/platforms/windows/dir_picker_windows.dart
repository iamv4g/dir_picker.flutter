import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../location/file_system_entry.dart';
import '../../location/picked_location.dart';
import '../../options/pick_options.dart';
import '../../platform_interface/dir_picker_platform.dart';
import '../io_entries.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Win32 type aliases
// ─────────────────────────────────────────────────────────────────────────────

typedef HRESULT = Int32;
typedef DWORD = Uint32;
typedef LPVOID = Pointer<Void>;
typedef ULONG = Uint32;

// ─────────────────────────────────────────────────────────────────────────────
// Win32 constants
// ─────────────────────────────────────────────────────────────────────────────

const int _coinitApartmentThreaded = 0x2;
const int _clsctxAll = 23; // CLSCTX_INPROC_SERVER | CLSCTX_LOCAL_SERVER | ...
const int _fosPickFolders = 0x20;
const int _fosForceFileSystem = 0x40;
const int _gaRootOwner = 3; // GetAncestor: GA_ROOTOWNER
// HRESULT_FROM_WIN32(ERROR_CANCELLED), returned by Show when the user cancels.
const int _hresultCancelled = 0x800704C7;
const int _sigdnFileSysPath = 0x80058000; // SIGDN_FILESYSPATH

// ─────────────────────────────────────────────────────────────────────────────
// GUID struct (matches Windows GUID layout)
// ─────────────────────────────────────────────────────────────────────────────

@Packed(4)
base class _GUID extends Struct {
  @Uint32()
  external int data1;

  @Uint16()
  external int data2;

  @Uint16()
  external int data3;

  // data4 is an 8-byte array; stored as Uint64 with little-endian byte order.
  @Uint64()
  external int data4;

  /// Parses a GUID string such as `{DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7}`
  /// into the struct fields.
  void parse(String guid) {
    final hex = guid.replaceAll(RegExp(r'[{}-]'), '');
    final bytes = ByteData(16);
    for (int i = 0; i < 16; i++) {
      bytes.setUint8(i, int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16));
    }
    data1 = bytes.getInt32(0);
    data2 = bytes.getInt16(4);
    data3 = bytes.getInt16(6);
    // data4 is a byte array — preserve byte order with little-endian read.
    data4 = bytes.getInt64(8, Endian.little);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COM function bindings (ole32.dll)
// ─────────────────────────────────────────────────────────────────────────────

final _ole32 = DynamicLibrary.open('ole32.dll');

final _coInitializeEx = _ole32
    .lookupFunction<
      HRESULT Function(LPVOID, DWORD),
      int Function(Pointer<Void>, int)
    >('CoInitializeEx');

final _coUninitialize = _ole32.lookupFunction<Void Function(), void Function()>(
  'CoUninitialize',
);

final _coCreateInstance = _ole32
    .lookupFunction<
      HRESULT Function(
        Pointer<_GUID>,
        LPVOID,
        DWORD,
        Pointer<_GUID>,
        Pointer<Pointer<Void>>,
      ),
      int Function(
        Pointer<_GUID>,
        Pointer<Void>,
        int,
        Pointer<_GUID>,
        Pointer<Pointer<Void>>,
      )
    >('CoCreateInstance');

final _user32 = DynamicLibrary.open('user32.dll');
final _kernel32 = DynamicLibrary.open('kernel32.dll');

final _getForegroundWindow = _user32
    .lookupFunction<IntPtr Function(), int Function()>('GetForegroundWindow');

final _getAncestor = _user32
    .lookupFunction<IntPtr Function(IntPtr, Uint32), int Function(int, int)>(
      'GetAncestor',
    );

final _getWindowThreadProcessId = _user32
    .lookupFunction<
      Uint32 Function(IntPtr, Pointer<Uint32>),
      int Function(int, Pointer<Uint32>)
    >('GetWindowThreadProcessId');

final _findWindowEx = _user32
    .lookupFunction<
      IntPtr Function(IntPtr, IntPtr, Pointer<Utf16>, Pointer<Utf16>),
      int Function(int, int, Pointer<Utf16>, Pointer<Utf16>)
    >('FindWindowExW');

final _isWindowVisible = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'IsWindowVisible',
    );

final _getCurrentProcessId = _kernel32
    .lookupFunction<Uint32 Function(), int Function()>('GetCurrentProcessId');

final _coTaskMemFree = _ole32
    .lookupFunction<Void Function(LPVOID), void Function(Pointer<Void>)>(
      'CoTaskMemFree',
    );

// ─────────────────────────────────────────────────────────────────────────────
// COM vtable helper
// ─────────────────────────────────────────────────────────────────────────────

/// Gets a function pointer from a COM object's vtable at the given [index].
Pointer<NativeFunction<T>> _vtableEntry<T extends Function>(
  Pointer<Void> comObj,
  int index,
) {
  // COM object layout: first pointer is vtable pointer
  final vtable = comObj.cast<Pointer<Pointer<NativeFunction<T>>>>().value;
  return (vtable + index).value;
}

// ─────────────────────────────────────────────────────────────────────────────
// COM vtable function signatures
// ─────────────────────────────────────────────────────────────────────────────

// IUnknown::Release (vtable index 2)
typedef _ReleaseNative = ULONG Function(Pointer<Void>);
typedef _ReleaseDart = int Function(Pointer<Void>);

// IFileDialog::SetOptions (vtable index 9)
typedef _SetOptionsNative = HRESULT Function(Pointer<Void>, DWORD);
typedef _SetOptionsDart = int Function(Pointer<Void>, int);

// IFileDialog::GetOptions (vtable index 10)
typedef _GetOptionsNative = HRESULT Function(Pointer<Void>, Pointer<DWORD>);
typedef _GetOptionsDart = int Function(Pointer<Void>, Pointer<Uint32>);

// IModalWindow::Show (vtable index 3)
typedef _ShowNative = HRESULT Function(Pointer<Void>, IntPtr);
typedef _ShowDart = int Function(Pointer<Void>, int);

// IFileDialog::GetResult (vtable index 20)
typedef _GetResultNative =
    HRESULT Function(Pointer<Void>, Pointer<Pointer<Void>>);
typedef _GetResultDart = int Function(Pointer<Void>, Pointer<Pointer<Void>>);

// IShellItem::GetDisplayName (vtable index 5)
typedef _GetDisplayNameNative =
    HRESULT Function(Pointer<Void>, Uint32, Pointer<Pointer<Utf16>>);
typedef _GetDisplayNameDart =
    int Function(Pointer<Void>, int, Pointer<Pointer<Utf16>>);

// IFileDialog::SetTitle (vtable index 17), SetOkButtonLabel (vtable index 18)
typedef _SetStringNative = HRESULT Function(Pointer<Void>, Pointer<Utf16>);
typedef _SetStringDart = int Function(Pointer<Void>, Pointer<Utf16>);

// ─────────────────────────────────────────────────────────────────────────────
// DirPickerWindows — platform implementation
// ─────────────────────────────────────────────────────────────────────────────

class DirPickerWindows extends DirPickerPlatform {
  static void registerWith() {
    DirPickerPlatform.instance = DirPickerWindows();
  }

  /// Shows a Windows folder picker dialog and returns the selected directory
  /// as a [Uri], or `null` if the user cancelled. Any other failure throws.
  ///
  /// Runs on a separate isolate because the COM dialog blocks the calling
  /// thread until the user closes it.
  /// The dialog is owned by the app's window, so it stays on top of it and
  /// the window can't be used until the dialog closes.
  @override
  Future<PickedLocation?> pick({PickOptions? options}) async {
    final opts = options is WindowsOptions ? options : const WindowsOptions();
    final owner = _ownerWindow();
    final path = await Isolate.run(
      () => _pickSync(opts.title, opts.acceptLabel, owner),
    );
    if (path == null) return null;
    return IOPickedLocation(Uri.directory(path, windows: true));
  }

  static String? _pickSync(String title, String acceptLabel, int owner) =>
      _withCom(() {
        final dialog = _createDialog(title, acceptLabel);
        try {
          return _showDialog(dialog, owner);
        } finally {
          _release(dialog);
        }
      });

  /// The window to own the dialog, or 0 for none: the foreground window if
  /// it belongs to this app, otherwise the app's visible Flutter runner
  /// window.
  @visibleForTesting
  static int debugOwnerWindow() => _ownerWindow();

  static int _ownerWindow() {
    final processId = _getCurrentProcessId();
    final pid = calloc<Uint32>();
    bool isOurs(int hwnd) {
      _getWindowThreadProcessId(hwnd, pid);
      return pid.value == processId;
    }

    try {
      final foreground = _getForegroundWindow();
      if (foreground != 0 && isOurs(foreground)) {
        return _getAncestor(foreground, _gaRootOwner);
      }

      // The class the Flutter app template registers for its window.
      final className = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
      try {
        var hwnd = 0;
        while ((hwnd = _findWindowEx(0, hwnd, className, nullptr)) != 0) {
          if (isOurs(hwnd) && _isWindowVisible(hwnd) != 0) return hwnd;
        }
        return 0;
      } finally {
        calloc.free(className);
      }
    } finally {
      calloc.free(pid);
    }
  }

  /// The `FILEOPENDIALOGOPTIONS` that [pick] shows the dialog with.
  @visibleForTesting
  static int debugDialogOptions() => _withCom(() {
    const defaults = WindowsOptions();
    final dialog = _createDialog(defaults.title, defaults.acceptLabel);
    try {
      return _getOptions(dialog);
    } finally {
      _release(dialog);
    }
  });

  /// Runs [body] with COM initialized as a single-threaded apartment, which
  /// the shell dialogs need.
  static T _withCom<T>(T Function() body) {
    final hr = _coInitializeEx(nullptr, _coinitApartmentThreaded);
    _check(hr, 'CoInitializeEx');
    try {
      return body();
    } finally {
      _coUninitialize();
    }
  }

  /// Creates an `IFileOpenDialog` that only accepts file system folders.
  static Pointer<Void> _createDialog(String title, String acceptLabel) {
    // CLSID_FileOpenDialog: {DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7}
    final clsid = calloc<_GUID>()
      ..ref.parse('{DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7}');

    // IID_IFileOpenDialog: {D57C7288-D4AD-4768-BE02-9D969532D960}
    final iid = calloc<_GUID>()
      ..ref.parse('{D57C7288-D4AD-4768-BE02-9D969532D960}');

    final ppDialog = calloc<Pointer<Void>>();

    try {
      _check(
        _coCreateInstance(clsid, nullptr, _clsctxAll, iid, ppDialog),
        'CoCreateInstance',
      );
      final dialog = ppDialog.value;

      try {
        // Add to the default options rather than replacing them, so
        // FOS_PATHMUSTEXIST and FOS_NOCHANGEDIR stay set. FOS_FORCEFILESYSTEM
        // stops the user from picking virtual folders such as "This PC",
        // which have no file system path.
        final setOptions = _vtableEntry<_SetOptionsNative>(
          dialog,
          9,
        ).asFunction<_SetOptionsDart>();
        _check(
          setOptions(
            dialog,
            _getOptions(dialog) | _fosPickFolders | _fosForceFileSystem,
          ),
          'SetOptions',
        );

        _setString(dialog, 17, title); // IFileDialog::SetTitle
        _setString(dialog, 18, acceptLabel); // IFileDialog::SetOkButtonLabel

        return dialog;
      } catch (_) {
        _release(dialog);
        rethrow;
      }
    } finally {
      calloc.free(clsid);
      calloc.free(iid);
      calloc.free(ppDialog);
    }
  }

  /// Calls the `IFileDialog` string setter at vtable [index].
  static void _setString(Pointer<Void> dialog, int index, String value) {
    final valuePtr = value.toNativeUtf16();
    try {
      final setString = _vtableEntry<_SetStringNative>(
        dialog,
        index,
      ).asFunction<_SetStringDart>();
      setString(dialog, valuePtr);
    } finally {
      calloc.free(valuePtr);
    }
  }

  static int _getOptions(Pointer<Void> dialog) {
    final pOptions = calloc<Uint32>();
    try {
      final getOptions = _vtableEntry<_GetOptionsNative>(
        dialog,
        10,
      ).asFunction<_GetOptionsDart>();
      _check(getOptions(dialog, pOptions), 'GetOptions');
      return pOptions.value;
    } finally {
      calloc.free(pOptions);
    }
  }

  /// Shows [dialog] and returns the picked folder's path, or `null` if the
  /// user cancelled.
  static String? _showDialog(Pointer<Void> dialog, int owner) {
    // Show the dialog (blocks until user closes)
    final show = _vtableEntry<_ShowNative>(dialog, 3).asFunction<_ShowDart>();
    final hr = show(dialog, owner);
    if (hr.toUnsigned(32) == _hresultCancelled) return null;
    _check(hr, 'Show');

    // Get the selected folder as IShellItem
    final ppItem = calloc<Pointer<Void>>();
    final ppszName = calloc<Pointer<Utf16>>();
    try {
      final getResult = _vtableEntry<_GetResultNative>(
        dialog,
        20,
      ).asFunction<_GetResultDart>();
      _check(getResult(dialog, ppItem), 'GetResult');
      final item = ppItem.value;

      try {
        // Get the file system path from IShellItem
        final getDisplayName = _vtableEntry<_GetDisplayNameNative>(
          item,
          5,
        ).asFunction<_GetDisplayNameDart>();
        _check(
          getDisplayName(item, _sigdnFileSysPath, ppszName),
          'GetDisplayName',
        );

        final path = ppszName.value.toDartString();
        _coTaskMemFree(ppszName.value.cast());
        return path;
      } finally {
        _release(item);
      }
    } finally {
      calloc.free(ppItem);
      calloc.free(ppszName);
    }
  }

  /// Throws if [hr] is a failure `HRESULT`.
  static void _check(int hr, String step) {
    if (hr >= 0) return;
    final code = hr.toUnsigned(32).toRadixString(16).toUpperCase();
    throw Exception('PLATFORM_ERROR: $step failed with HRESULT 0x$code');
  }

  static void _release(Pointer<Void> comObj) {
    final release = _vtableEntry<_ReleaseNative>(
      comObj,
      2,
    ).asFunction<_ReleaseDart>();
    release(comObj);
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

    return listIoEntries(Directory.fromUri(uri), recursive: recursive);
  }
}
