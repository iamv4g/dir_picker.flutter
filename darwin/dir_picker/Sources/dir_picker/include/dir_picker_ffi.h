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

/// Walk a directory and report its entries via NativePort, in batches.
///
/// Messages sent to native_port:
/// - Batch:      [3, jsonArray] (zero or more)
/// - Done:       [1] (also after dir_picker_cancel_entries)
/// - Error:      [2, errorCode, errorMessage] (instead of Done)
///
/// @param native_port   Dart NativePort for result reporting
/// @param uri           Directory URI (nullable only for invalid input handling)
/// @param recursive     Whether to walk nested descendants
void dir_picker_stream_entries(int64_t native_port, const char* uri, bool recursive);

/// Stop the dir_picker_stream_entries walk that reports to native_port. It
/// sends no more batches, only Done.
///
/// @param native_port   The port passed to dir_picker_stream_entries
void dir_picker_cancel_entries(int64_t native_port);

/// Create a bookmark of a directory, as a base64 token, and report it via
/// NativePort. On macOS the bookmark is security-scoped.
///
/// Messages sent to native_port:
/// - Success:    [0, token]
/// - Error:      [2, errorCode, errorMessage]
///
/// @param native_port   Dart NativePort for result reporting
/// @param uri           file:// URI of a picked or restored directory
void dir_picker_persist(int64_t native_port, const char* uri);

/// Resolve a token from dir_picker_persist and start accessing the directory,
/// until dir_picker_release.
///
/// Messages sent to native_port:
/// - Success:    [0, directoryUri]
/// - Unusable:   [1] (invalid, unresolvable or revoked token)
///
/// @param native_port   Dart NativePort for result reporting
/// @param token         Token from dir_picker_persist
void dir_picker_restore(int64_t native_port, const char* token);

/// Stop accessing the directory a token from dir_picker_persist points to.
///
/// Messages sent to native_port:
/// - Done:       [1]
///
/// @param native_port   Dart NativePort for result reporting
/// @param token         Token from dir_picker_persist
void dir_picker_release(int64_t native_port, const char* token);

#endif /* dir_picker_ffi_h */
