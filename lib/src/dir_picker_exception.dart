/// A failure reported by a platform's picker, file system or permission
/// store.
///
/// [code] says what failed, so an app can react without parsing [message]:
///
/// ```dart
/// try {
///   await DirPicker.pick();
/// } on DirPickerException catch (e) {
///   if (e.code == DirPickerException.alreadyActive) return;
///   rethrow;
/// }
/// ```
///
/// Misuse of the API, such as a location from another platform or a method
/// the platform doesn't support, throws [ArgumentError], [UnsupportedError]
/// or [StateError] instead.
class DirPickerException implements Exception {
  const DirPickerException(this.code, [this.message]);

  /// What failed: one of the constants below. Compare with them rather than
  /// with literals; a platform may also report a code not listed here.
  final String code;

  /// A description of the failure from the platform, for logs. Its wording
  /// isn't part of the API.
  final String? message;

  /// `DirPicker.pick` was called while another pick was still open.
  static const alreadyActive = 'ALREADY_ACTIVE';

  /// The picker couldn't be shown or failed: on Android, launching it; on
  /// Linux, zenity or kdialog exiting with an error; on web, an error from
  /// `showDirectoryPicker()` other than the user cancelling.
  static const pickerError = 'PICKER_ERROR';

  /// A platform call failed: on Windows, a COM call (the message has the
  /// `HRESULT`); on iOS, no view controller to present the picker from; on
  /// web, `WebPickedLocation.requestAccess` called without a user gesture.
  static const platformError = 'PLATFORM_ERROR';

  /// Android: no Activity is attached to the engine, so the picker can't be
  /// shown.
  static const noActivity = 'NO_ACTIVITY';

  /// Android: the plugin has no application context yet.
  static const noContext = 'NO_CONTEXT';

  /// The location's URI can't be opened as a directory on this platform.
  static const invalidUri = 'INVALID_URI';

  /// The picked directory itself couldn't be read: it was deleted, isn't a
  /// directory, or access to it was lost.
  static const listError = 'LIST_ERROR';

  /// `DirPicker.persist` couldn't keep access: on Android, no grant to
  /// persist; on iOS and macOS, the bookmark couldn't be created; on web,
  /// IndexedDB couldn't store the handle.
  static const persistError = 'PERSIST_ERROR';

  /// `DirPicker.restore` couldn't check the persisted permissions (Android)
  /// or read IndexedDB (web).
  static const restoreError = 'RESTORE_ERROR';

  /// `DirPicker.release` couldn't release the permission (Android) or
  /// delete the record (web).
  static const releaseError = 'RELEASE_ERROR';

  /// `DirPicker.persistedTokens` couldn't read the permissions (Android) or
  /// IndexedDB (web).
  static const persistedTokensError = 'PERSISTED_TOKENS_ERROR';

  @override
  String toString() => message == null
      ? 'DirPickerException($code)'
      : 'DirPickerException($code): $message';
}
