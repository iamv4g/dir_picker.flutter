/// Options for directory picking.
sealed class PickOptions {
  const factory PickOptions.android({bool shouldPersist}) = AndroidOptions;

  const factory PickOptions.macos({String acceptLabel, String message}) =
      MacosOptions;

  const factory PickOptions.linux({String title, String acceptLabel}) =
      LinuxOptions;

  const factory PickOptions.windows({String title, String acceptLabel}) =
      WindowsOptions;
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
  /// Applied to XDG Desktop Portal (via `accept_label`) and zenity (via `--ok-label`).
  /// Not supported by kdialog.
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
