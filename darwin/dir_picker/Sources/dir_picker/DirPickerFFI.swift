import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
import DartApiDl

// MARK: - Init

@_cdecl("dir_picker_init_dart_api_dl")
public func dirPickerInitDartApiDL(_ data: UnsafeMutableRawPointer?) -> Int {
    guard let data = data else { return -1 }
    return Dart_InitializeApiDL(data)
}

// MARK: - Directory Picker

#if os(iOS)
private var activePickerHelper: DocumentPickerHelper?
private let pickerLock = NSLock()

@_cdecl("dir_picker_pick")
public func dirPickerPick(
    _ nativePort: Int64,
    _ acceptLabelPtr: UnsafePointer<CChar>?,
    _ messagePtr: UnsafePointer<CChar>?
) {
    // acceptLabel and message are macOS-only — ignored on iOS
    let reporter = DirPickerReporter(port: nativePort)

    DispatchQueue.main.async {
        guard let rootVC = getRootViewController() else {
            reporter.sendError(
                code: "PLATFORM_ERROR",
                message: "No root view controller available"
            )
            return
        }

        pickerLock.lock()
        let isActive = activePickerHelper != nil
        pickerLock.unlock()
        // UIKit ignores a second present while the picker is still being
        // presented, and nothing would ever report back.
        guard !isActive else {
            reporter.sendError(
                code: "ALREADY_ACTIVE",
                message: "A directory picker is already open"
            )
            return
        }

        let helper = DocumentPickerHelper()

        pickerLock.lock()
        activePickerHelper = helper
        pickerLock.unlock()

        helper.pick(from: topViewController(from: rootVC)) { url in
            pickerLock.lock()
            activePickerHelper = nil
            pickerLock.unlock()

            if let url = url {
                reporter.sendUriSuccess(url.absoluteString)
            } else {
                reporter.sendCancelled()
            }
        }
    }
}

/// The view controller at the top of the presentation stack above `root`.
/// UIKit ignores `present` on a controller that is already presenting.
private func topViewController(from root: UIViewController) -> UIViewController {
    var top = root
    while let presented = top.presentedViewController {
        top = presented
    }
    return top
}

private func getRootViewController() -> UIViewController? {
    if #available(iOS 15.0, *) {
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
    } else {
        return UIApplication.shared.keyWindow?.rootViewController
    }
}

#elseif os(macOS)

@_cdecl("dir_picker_pick")
public func dirPickerPick(
    _ nativePort: Int64,
    _ acceptLabelPtr: UnsafePointer<CChar>?,
    _ messagePtr: UnsafePointer<CChar>?
) {
    let reporter = DirPickerReporter(port: nativePort)
    // Copy C strings immediately — safe to free the Dart-side pointers after this call returns
    let acceptLabel = acceptLabelPtr.map { String(cString: $0) } ?? "Select"
    let message = messagePtr.map { String(cString: $0) } ?? "Choose a directory"

    PanelPickerHelper.pick(acceptLabel: acceptLabel, message: message) { url in
        if let url = url {
            reporter.sendUriSuccess(url.absoluteString)
        } else {
            reporter.sendCancelled()
        }
    }
}
#endif

@_cdecl("dir_picker_list_entries")
public func dirPickerListEntries(
    _ nativePort: Int64,
    _ uriPtr: UnsafePointer<CChar>?,
    _ recursive: Bool
) {
    let reporter = DirPickerReporter(port: nativePort)

    guard let uriString = uriPtr.map({ String(cString: $0) }),
          let rootUrl = URL(string: uriString) else {
        reporter.sendError(code: "INVALID_URI", message: "Invalid URI")
        return
    }

    DispatchQueue.global(qos: .userInitiated).async {
        let isAccessing = rootUrl.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                rootUrl.stopAccessingSecurityScopedResource()
            }
        }

        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [
            .nameKey,
            .isDirectoryKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ]

        do {
            // The enumerator returns nil instead of throwing for a missing
            // root, so check it up front to fail like contentsOfDirectory.
            guard try rootUrl.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                reporter.sendError(code: "LIST_ERROR", message: "Not a directory: \(rootUrl.path)")
                return
            }

            let urls: [URL]
            if recursive {
                urls = fileManager.enumerator(
                    at: rootUrl,
                    includingPropertiesForKeys: keys,
                    options: [],
                    errorHandler: nil
                )?.compactMap { $0 as? URL } ?? []
            } else {
                urls = try fileManager.contentsOfDirectory(
                    at: rootUrl,
                    includingPropertiesForKeys: keys,
                    options: []
                )
            }

            let entries = try urls.map { fileUrl in
                try makeEntryDictionary(fileUrl: fileUrl, rootUrl: rootUrl, keys: keys)
            }

            let jsonData = try JSONSerialization.data(withJSONObject: entries)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
            reporter.sendJsonSuccess(jsonString)
        } catch {
            reporter.sendError(code: "LIST_ERROR", message: error.localizedDescription)
        }
    }
}

private func makeEntryDictionary(
    fileUrl: URL,
    rootUrl: URL,
    keys: [URLResourceKey]
) throws -> [String: Any] {
    let resourceValues = try fileUrl.resourceValues(forKeys: Set(keys))
    let isDirectory = resourceValues.isDirectory ?? false

    // Foundation hands back decomposed (NFD) names. Return them precomposed
    // (NFC), as dart:io and the other platforms do, so they compare equal to
    // Dart string literals.
    return [
        "name": (resourceValues.name ?? fileUrl.lastPathComponent).precomposedStringWithCanonicalMapping,
        "relativePath": relativePath(for: fileUrl, rootUrl: rootUrl).precomposedStringWithCanonicalMapping,
        "isDirectory": isDirectory,
        "uri": fileUrl.absoluteString,
        "size": isDirectory ? NSNull() : (resourceValues.fileSize as Any? ?? NSNull()),
        "lastModified": resourceValues.contentModificationDate.map {
            Int64($0.timeIntervalSince1970 * 1000)
        } ?? NSNull(),
    ]
}

private func relativePath(for fileUrl: URL, rootUrl: URL) -> String {
    let rootPath = rootUrl.standardizedFileURL.path
    let filePath = fileUrl.standardizedFileURL.path

    if filePath == rootPath {
        return ""
    }

    let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
    if filePath.hasPrefix(prefix) {
        return String(filePath.dropFirst(prefix.count))
    }

    return fileUrl.lastPathComponent
}
