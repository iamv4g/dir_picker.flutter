import Foundation

/// Directories whose security scope this process keeps open, by path.
///
/// Access to a folder from the iOS document picker or from a resolved
/// bookmark belongs to that URL object: a URL rebuilt from the string Dart
/// holds has none. Keeping the URL, with access started, lets later calls for
/// the same location use it until `release(_:)`.
enum ScopedAccess {
    private static var kept: [String: (url: URL, isAccessing: Bool)] = [:]
    private static let lock = NSLock()

    /// Starts accessing `url` and keeps it. Does nothing if a URL for the same
    /// directory is already kept.
    static func keep(_ url: URL) {
        let key = self.key(for: url)
        lock.lock()
        defer { lock.unlock() }
        guard kept[key] == nil else { return }
        kept[key] = (url, url.startAccessingSecurityScopedResource())
    }

    /// The kept URL for the directory `uriString` points to, or else a new URL
    /// parsed from it.
    static func url(for uriString: String) -> URL? {
        guard let url = URL(string: uriString) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return kept[key(for: url)]?.url ?? url
    }

    /// Stops accessing the directory `url` points to, if it's kept.
    static func release(_ url: URL) {
        lock.lock()
        let entry = kept.removeValue(forKey: key(for: url))
        lock.unlock()
        if let entry = entry, entry.isAccessing {
            entry.url.stopAccessingSecurityScopedResource()
        }
    }

    private static func key(for url: URL) -> String {
        url.standardizedFileURL.path
    }
}
