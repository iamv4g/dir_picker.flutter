#if os(iOS)
import UIKit
import UniformTypeIdentifiers

/// Helper for UIDocumentPickerViewController operations.
///
/// Provides a simple async interface for picking directories via the system picker.
final class DocumentPickerHelper: NSObject {
    private var completion: ((URL?) -> Void)?
    private var retainSelf: DocumentPickerHelper?

    /// Pick a directory using the system document picker.
    ///
    /// - Parameters:
    ///   - viewController: The view controller to present the picker from
    ///   - initialDirectory: The folder to open in, if any (iOS 13+)
    ///   - completion: Called with the selected directory URL, or nil if cancelled
    func pick(
        from viewController: UIViewController,
        initialDirectory: URL? = nil,
        completion: @escaping (URL?) -> Void
    ) {
        self.completion = completion
        // Retain self until picker completes
        self.retainSelf = self

        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        } else {
            picker = UIDocumentPickerViewController(
                documentTypes: ["public.folder"],
                in: .open
            )
        }
        picker.delegate = self
        picker.allowsMultipleSelection = false
        picker.modalPresentationStyle = .formSheet
        if #available(iOS 13.0, *), let initialDirectory = initialDirectory {
            picker.directoryURL = initialDirectory
        }

        viewController.present(picker, animated: true)
    }

    private func finish(with url: URL?) {
        completion?(url)
        completion = nil
        retainSelf = nil
    }
}

// MARK: - UIDocumentPickerDelegate

extension DocumentPickerHelper: UIDocumentPickerDelegate {
    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        finish(with: urls.first)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finish(with: nil)
    }
}
#endif
