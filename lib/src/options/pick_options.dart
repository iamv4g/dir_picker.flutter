/// Options for directory picking.
sealed class PickOptions {
  const factory PickOptions.android({bool shouldPersist}) = AndroidOptions;

  const factory PickOptions.macos({String acceptLabel, String message}) =
      MacosOptions;

  const factory PickOptions.linux({String title, String acceptLabel}) =
      LinuxOptions;

  const factory PickOptions.windows({String title, String acceptLabel}) =
      WindowsOptions;

  const factory PickOptions.web({
    WebPermissionMode mode,
    String? id,
    WebStartIn? startIn,
  }) = WebOptions;
}

/// Options for directory picking on Android.
class AndroidOptions implements PickOptions {
  const AndroidOptions({this.shouldPersist = false});

  /// Whether to take persistable URI permission so the app can access
  /// the directory across reboots without re-prompting the user.
  ///
  /// Defaults to `false`.
  final bool shouldPersist;
}

/// Options for directory picking on macOS.
class MacosOptions implements PickOptions {
  const MacosOptions({
    this.acceptLabel = 'Select',
    this.message = 'Choose a directory',
  });

  /// Label for the confirmation button.
  ///
  /// Applied via `NSOpenPanel.prompt`.
  final String acceptLabel;

  /// Descriptive message shown inside the panel above the browser.
  ///
  /// Applied via `NSOpenPanel.message`. macOS-specific — no equivalent on other platforms.
  final String message;
}

/// Options for directory picking on Linux.
class LinuxOptions implements PickOptions {
  const LinuxOptions({
    this.title = 'Select Directory',
    this.acceptLabel = 'Select',
  });

  /// Title shown in the directory picker dialog.
  ///
  /// Applied to XDG Desktop Portal, zenity, and kdialog.
  final String title;

  /// Label for the confirmation button.
  ///
  /// Applied to XDG Desktop Portal (via `accept_label`). Not supported by the
  /// zenity and kdialog fallbacks.
  final String acceptLabel;
}

/// Options for directory picking on Windows.
class WindowsOptions implements PickOptions {
  const WindowsOptions({
    this.title = 'Select Directory',
    this.acceptLabel = 'Select',
  });

  /// Title shown in the directory picker dialog.
  ///
  /// Applied via `IFileDialog::SetTitle`.
  final String title;

  /// Label for the confirmation button.
  ///
  /// Applied via `IFileDialog::SetOkButtonLabel`.
  final String acceptLabel;
}

/// Options for directory picking on the web, passed to
/// `window.showDirectoryPicker()`.
class WebOptions implements PickOptions {
  const WebOptions({this.mode = WebPermissionMode.read, this.id, this.startIn})
    : assert(
        id == null || (id.length > 0 && id.length <= 32),
        'id must be 1 to 32 characters (letters, digits, "_" or "-")',
      );

  /// The access the browser asks the user for.
  ///
  /// With [WebPermissionMode.readwrite], the returned handle can create,
  /// change and delete files without asking again. Defaults to
  /// [WebPermissionMode.read].
  final WebPermissionMode mode;

  /// Lets the browser remember the last folder picked for this purpose and
  /// open there next time, separately from pickers with other ids.
  ///
  /// At most 32 characters: letters, digits, `_` and `-`.
  final String? id;

  /// A well-known folder to open in when the browser has no remembered
  /// folder for [id].
  final WebStartIn? startIn;
}

/// The permission `showDirectoryPicker()` requests.
enum WebPermissionMode { read, readwrite }

/// Well-known folders `showDirectoryPicker()` can open in.
enum WebStartIn { desktop, documents, downloads, music, pictures, videos }
