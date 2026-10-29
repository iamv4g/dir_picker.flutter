import '../../location/file_system_entry.dart';
import '../../location/picked_location.dart';
import '../entries_json.dart';

// Decoders for the messages DirPickerReporter.swift posts to the Dart port:
// - Success:    [0, string]
// - Cancelled:  [1]
// - Error:      [2, errorCode, errorMessage]

/// Decodes a `dir_picker_pick` or `dir_picker_restore` result. Returns
/// `null` when the picker was cancelled or the token can't be restored.
PickedLocation? decodePickMessage(Object? message) {
  switch (message) {
    case [0, final String uri]:
      return IOPickedLocation(Uri.parse(uri));
    case [1]:
      return null;
    default:
      throw _decodeFailure(message);
  }
}

/// Decodes a `dir_picker_list_entries` result.
List<FileSystemEntry> decodeListEntriesMessage(Object? message) {
  switch (message) {
    case [0, final String json]:
      return decodeEntriesJson(json);
    default:
      throw _decodeFailure(message);
  }
}

Object _decodeFailure(Object? message) => switch (message) {
  [2, final String code, final String msg] => Exception('$code: $msg'),
  [0 || 1 || 2, ...] => StateError('Invalid message format'),
  [final int type, ...] => StateError('Unknown message type: $type'),
  _ => StateError('Invalid message format'),
};

/// Decodes a `dir_picker_persist` result: the token.
String decodePersistMessage(Object? message) {
  switch (message) {
    case [0, final String token]:
      return token;
    default:
      throw _decodeFailure(message);
  }
}

/// Decodes a `dir_picker_release` result.
void decodeReleaseMessage(Object? message) {
  switch (message) {
    case [1]:
      return;
    default:
      throw _decodeFailure(message);
  }
}
