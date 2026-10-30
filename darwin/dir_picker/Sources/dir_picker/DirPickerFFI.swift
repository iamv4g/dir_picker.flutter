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
    _ messagePtr: UnsafePointer<CChar>?,
    _ initialDirectoryPtr: UnsafePointer<CChar>?
) {
    // acceptLabel and message are macOS-only — ignored on iOS
    let reporter = DirPickerReporter(port: nativePort)
    // Copy now: Dart frees the C string right after this call returns.
    let initialDirectory = initialDirectoryPtr.flatMap { URL(string: String(cString: $0)) }

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

        helper.pick(from: topViewController(from: rootVC), initialDirectory: initialDirectory) { url in
            pickerLock.lock()
            activePickerHelper = nil
            pickerLock.unlock()

            if let url = url {
                // The access the picker granted belongs to this URL object.
                ScopedAccess.keep(url)
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
    _ messagePtr: UnsafePointer<CChar>?,
    _ initialDirectoryPtr: UnsafePointer<CChar>?
) {
    let reporter = DirPickerReporter(port: nativePort)
    // Copy C strings immediately — safe to free the Dart-side pointers after this call returns
    let acceptLabel = acceptLabelPtr.map { String(cString: $0) } ?? "Select"
    let message = messagePtr.map { String(cString: $0) } ?? "Choose a directory"
    let initialDirectory = initialDirectoryPtr.flatMap { URL(string: String(cString: $0)) }

    PanelPickerHelper.pick(
        acceptLabel: acceptLabel,
        message: message,
        initialDirectory: initialDirectory
    ) { url in
        if let url = url {
            reporter.sendUriSuccess(url.absoluteString)
        } else {
            reporter.sendCancelled()
        }
    }
}
#endif

// MARK: - Entries

/// Entries sent per batch message.
private let entriesBatchSize = 200

@_cdecl("dir_picker_stream_entries")
public func dirPickerStreamEntries(
    _ nativePort: Int64,
    _ uriPtr: UnsafePointer<CChar>?,
    _ recursive: Bool
) {
    let reporter = DirPickerReporter(port: nativePort)

    guard let uriString = uriPtr.map({ String(cString: $0) }),
          let rootUrl = ScopedAccess.url(for: uriString) else {
        reporter.sendError(code: "INVALID_URI", message: "Invalid URI")
        return
    }

    // Registered before returning, so a cancel that follows always finds it.
    EntryStreams.start(nativePort)

    DispatchQueue.global(qos: .userInitiated).async {
        defer { EntryStreams.finish(nativePort) }

        let isAccessing = rootUrl.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                rootUrl.stopAccessingSecurityScopedResource()
            }
        }

        let keys: [URLResourceKey] = [
            .nameKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ]

        do {
            // The enumerator returns nil instead of throwing for a missing
            // root, so check it up front.
            guard try rootUrl.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                reporter.sendError(code: "LIST_ERROR", message: "Not a directory: \(rootUrl.path)")
                return
            }

            // An unreadable subdirectory is skipped; only the root fails.
            let rootPath = rootUrl.standardizedFileURL.path
            var rootError: Error?
            let enumerator = FileManager.default.enumerator(
                at: rootUrl,
                includingPropertiesForKeys: keys,
                options: recursive ? [] : [.skipsSubdirectoryDescendants],
                errorHandler: { url, error in
                    if url.standardizedFileURL.path == rootPath {
                        rootError = error
                    }
                    return true
                }
            )

            var batch: [[String: Any]] = []
            while !EntryStreams.isCancelled(nativePort) {
                let entry = try autoreleasepool { () -> [String: Any]? in
                    guard let fileUrl = enumerator?.nextObject() as? URL else { return nil }
                    return try makeEntryDictionary(fileUrl: fileUrl, rootUrl: rootUrl, keys: keys)
                }
                guard let entry = entry else { break }
                batch.append(entry)
                if batch.count == entriesBatchSize {
                    try reporter.sendBatch(batch)
                    batch.removeAll(keepingCapacity: true)
                }
            }

            if let rootError = rootError {
                reporter.sendError(code: "LIST_ERROR", message: rootError.localizedDescription)
                return
            }
            if !batch.isEmpty {
                try reporter.sendBatch(batch)
            }
            reporter.sendDone()
        } catch {
            reporter.sendError(code: "LIST_ERROR", message: error.localizedDescription)
        }
    }
}

@_cdecl("dir_picker_cancel_entries")
public func dirPickerCancelEntries(_ nativePort: Int64) {
    EntryStreams.cancel(nativePort)
}

/// The entry streams that are running, by port, and whether Dart cancelled
/// them.
private enum EntryStreams {
    private static var cancelled: [Int64: Bool] = [:]
    private static let lock = NSLock()

    static func start(_ port: Int64) {
        lock.lock()
        defer { lock.unlock() }
        cancelled[port] = false
    }

    static func cancel(_ port: Int64) {
        lock.lock()
        defer { lock.unlock() }
        if cancelled[port] != nil {
            cancelled[port] = true
        }
    }

    static func isCancelled(_ port: Int64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled[port] ?? true
    }

    static func finish(_ port: Int64) {
        lock.lock()
        defer { lock.unlock() }
        cancelled[port] = nil
    }
}

// MARK: - Persistence

#if os(macOS)
private let bookmarkCreationOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
private let bookmarkResolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
#else
private let bookmarkCreationOptions: URL.BookmarkCreationOptions = [.minimalBookmark]
private let bookmarkResolutionOptions: URL.BookmarkResolutionOptions = [.withoutUI]
#endif

@_cdecl("dir_picker_persist")
public func dirPickerPersist(_ nativePort: Int64, _ uriPtr: UnsafePointer<CChar>?) {
    let reporter = DirPickerReporter(port: nativePort)

    guard let url = uriPtr.flatMap({ ScopedAccess.url(for: String(cString: $0)) }) else {
        reporter.sendError(code: "INVALID_URI", message: "Invalid URI")
        return
    }

    DispatchQueue.global(qos: .userInitiated).async {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let bookmark = try url.bookmarkData(
                options: bookmarkCreationOptions,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            reporter.sendTokenSuccess(bookmark.base64EncodedString())
        } catch {
            reporter.sendError(code: "PERSIST_ERROR", message: error.localizedDescription)
        }
    }
}

@_cdecl("dir_picker_restore")
public func dirPickerRestore(_ nativePort: Int64, _ tokenPtr: UnsafePointer<CChar>?) {
    let reporter = DirPickerReporter(port: nativePort)
    let token = tokenPtr.map { String(cString: $0) } ?? ""

    DispatchQueue.global(qos: .userInitiated).async {
        guard let url = resolveBookmark(token) else {
            reporter.sendCancelled()
            return
        }
        // Access lasts until dir_picker_release or the process exits.
        ScopedAccess.keep(url)
        reporter.sendUriSuccess(url.absoluteString)
    }
}

@_cdecl("dir_picker_release")
public func dirPickerRelease(_ nativePort: Int64, _ tokenPtr: UnsafePointer<CChar>?) {
    let reporter = DirPickerReporter(port: nativePort)
    let token = tokenPtr.map { String(cString: $0) } ?? ""

    DispatchQueue.global(qos: .userInitiated).async {
        if let url = resolveBookmark(token) {
            ScopedAccess.release(url)
        }
        reporter.sendCancelled()
    }
}

/// The URL a base64 bookmark points to, or nil when it isn't a bookmark or
/// can't be resolved, such as when the folder was deleted. A stale bookmark
/// still resolves: `DirPicker.restore` tells apps to persist it again.
private func resolveBookmark(_ token: String) -> URL? {
    guard let bookmark = Data(base64Encoded: token) else { return nil }
    var isStale = false
    return try? URL(
        resolvingBookmarkData: bookmark,
        options: bookmarkResolutionOptions,
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
    )
}

private func makeEntryDictionary(
    fileUrl: URL,
    rootUrl: URL,
    keys: [URLResourceKey]
) throws -> [String: Any] {
    let linkValues = try fileUrl.resourceValues(forKeys: Set(keys))
    // Report a symbolic link as what it points to, as dart:io does on Linux
    // and Windows. The enumerator still doesn't descend into it.
    let resourceValues =
        linkValues.isSymbolicLink == true
        ? targetValues(ofLink: fileUrl, keys: Set(keys)) : linkValues
    let isDirectory = resourceValues.isDirectory ?? false

    // Foundation hands back decomposed (NFD) names. Return them precomposed
    // (NFC), as dart:io and the other platforms do, so they compare equal to
    // Dart string literals.
    return [
        "name": (linkValues.name ?? fileUrl.lastPathComponent).precomposedStringWithCanonicalMapping,
        "relativePath": relativePath(for: fileUrl, rootUrl: rootUrl).precomposedStringWithCanonicalMapping,
        "isDirectory": isDirectory,
        "uri": fileUrl.absoluteString,
        "size": isDirectory ? NSNull() : (resourceValues.fileSize as Any? ?? NSNull()),
        "lastModified": resourceValues.contentModificationDate.map {
            Int64($0.timeIntervalSince1970 * 1000)
        } ?? NSNull(),
    ]
}

/// The values of the file a symbolic link points to, or no values for a
/// broken link.
private func targetValues(ofLink link: URL, keys: Set<URLResourceKey>) -> URLResourceValues {
    guard let values = try? link.resolvingSymlinksInPath().resourceValues(forKeys: keys),
        values.isSymbolicLink != true
    else { return URLResourceValues() }
    return values
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
