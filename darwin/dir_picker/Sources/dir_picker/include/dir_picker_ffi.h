#ifndef dir_picker_ffi_h
#define dir_picker_ffi_h

#include <stdbool.h>
#include <stdint.h>

/// Initialize Dart API for NativePort communication.
/// Must be called before using dir_picker_pick.
///
/// @param data Pointer from NativeApi.initializeApiDLData
/// @return 0 on success, -1 on failure
intptr_t dir_picker_init_dart_api_dl(void* data);

/// Show a directory picker dialog and report the result via NativePort.
///
/// Messages sent to native_port:
/// - Success:    [0, directoryUri]
/// - Cancelled:  [1]
/// - Error:      [2, errorCode, errorMessage]
///
/// @param native_port        Dart NativePort for result reporting
/// @param accept_label       Label for the confirmation button (macOS only, nullable)
/// @param message            Descriptive text in the panel (macOS only, nullable)
/// @param initial_directory  file:// URI of the folder to open in (nullable)
void dir_picker_pick(int64_t native_port, const char* accept_label, const char* message,
                     const char* initial_directory);

/// List directory entries and report the result via NativePort.
///
/// Messages sent to native_port:
/// - Success:    [0, jsonString]
/// - Error:      [2, errorCode, errorMessage]
///
/// @param native_port   Dart NativePort for result reporting
/// @param uri           Directory URI (nullable only for invalid input handling)
/// @param recursive     Whether to walk nested descendants
void dir_picker_list_entries(int64_t native_port, const char* uri, bool recursive);

#endif /* dir_picker_ffi_h */
