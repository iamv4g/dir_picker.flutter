#if os(macOS)
import AppKit

/// Helper for NSOpenPanel operations on macOS.
///
/// Provides a simple async interface for picking directories via the system panel.
class PanelPickerHelper {
    /// Pick a directory using the system open panel.
    ///
    /// - Parameters:
    ///   - acceptLabel: Label for the confirmation button. Defaults to `"Select"`.
    ///   - message:     Descriptive text shown in the panel. Defaults to `"Choose a directory"`.
    ///   - initialDirectory: The folder to open in, if any.
    ///   - completion:  Called with the selected directory URL, or nil if cancelled.
    static func pick(
        acceptLabel: String = "Select",
        message: String = "Choose a directory",
        initialDirectory: URL? = nil,
        completion: @escaping (URL?) -> Void
    ) {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = acceptLabel
            panel.message = message
            if let initialDirectory = initialDirectory {
                panel.directoryURL = initialDirectory
            }

            if panel.runModal() == .OK {
                completion(panel.url)
            } else {
                completion(nil)
            }
        }
    }
}
#endif
