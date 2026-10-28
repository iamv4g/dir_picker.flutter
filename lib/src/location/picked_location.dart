/// Base class for the result of a directory pick operation.
abstract class PickedLocation {
  /// The URI of the selected directory.
  ///
  /// Returns `null` on web — browsers do not expose full filesystem paths
  /// for security reasons.
  Uri? get uri;
}

/// A [PickedLocation] on native platforms (Android, iOS, macOS, Windows, Linux).
class IOPickedLocation extends PickedLocation {
  IOPickedLocation(this._uri);

  final Uri _uri;

  @override
  Uri get uri => _uri;

  /// Two locations are equal when their [uri]s are equal.
  @override
  bool operator ==(Object other) =>
      other is IOPickedLocation && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;

  @override
  String toString() => 'IOPickedLocation($uri)';
}
