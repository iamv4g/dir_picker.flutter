import 'dart:io';

import '../location/picked_location.dart';

// Tokens for the Linux and Windows implementations. Apps there aren't
// sandboxed, so a picked path stays usable and the token is just its URI.

/// The token for [location]: its `file://` URI.
String persistIoLocation(PickedLocation location) {
  final uri = location.uri;
  if (uri == null || uri.scheme != 'file') {
    throw ArgumentError.value(
      location,
      'location',
      'persist requires a file:// location on this platform.',
    );
  }
  return uri.toString();
}

/// The location [token] points to, or `null` when it isn't a `file://` URI
/// or the directory no longer exists.
Future<PickedLocation?> restoreIoLocation(String token) async {
  final uri = Uri.tryParse(token);
  if (uri == null || uri.scheme != 'file') return null;
  final Directory directory;
  try {
    directory = Directory.fromUri(uri);
  } on UnsupportedError {
    // A URI that isn't a path on this platform, such as a Windows drive
    // path on Linux.
    return null;
  }
  return await directory.exists() ? IOPickedLocation(uri) : null;
}
