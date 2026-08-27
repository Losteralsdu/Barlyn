import Foundation
import OSLog
import Synchronization

/// Persistence for clipboard history.
///
/// Behind a protocol so tests never touch the user's real history file, and so a future
/// encrypted-at-rest implementation can be swapped in without changing the service above it.
nonisolated protocol ClipboardHistoryStorage: AnyObject, Sendable {
    func load() -> [ClipboardItem]
    func save(_ items: [ClipboardItem])
    func deleteAll()
}

/// JSON file in Application Support.
///
/// **Stored in plain text, deliberately and with a known cost.** Encrypting at rest needs a key,
/// and the only sensible place for one is the Keychain — which belongs with the credential work
/// in Phase 11 rather than being invented here. Until then the file is created `0600`
/// (owner-only) and lives inside the user's own container. This is recorded as an open task
/// rather than left implicit, because "clipboard history on disk" is the most sensitive thing
/// Barlyn stores.
final class FileClipboardHistoryStorage: ClipboardHistoryStorage {
    private let fileURL: URL
    /// Serialises reads and writes; the service may save from a background context.
    private let lock = Mutex<Void>(())

    init?(directoryName: String = "Barlyn", fileName: String = "clipboard-history.json") {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            AppLog.clipboard.error("No Application Support directory; clipboard history disabled")
            return nil
        }

        let directory = support.appending(path: directoryName)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        self.fileURL = directory.appending(path: fileName)
    }

    func load() -> [ClipboardItem] {
        lock.withLock { _ in
            guard let data = try? Data(contentsOf: fileURL) else { return [] }
            do {
                return try JSONDecoder().decode([ClipboardItem].self, from: data)
            } catch {
                // Never log the file's contents — only that it failed to parse.
                AppLog.clipboard.error("Clipboard history could not be decoded; starting empty")
                return []
            }
        }
    }

    func save(_ items: [ClipboardItem]) {
        lock.withLock { _ in
            do {
                let data = try JSONEncoder().encode(items)
                try data.write(to: fileURL, options: [.atomic])
                // Re-applied after every write: `.atomic` replaces the file, which would
                // otherwise inherit default permissions rather than keeping 0600.
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: fileURL.path
                )
            } catch {
                AppLog.clipboard.error(
                    "\(ClipboardError.writeFailed(detail: "encode or write").diagnosticDescription, privacy: .public)"
                )
            }
        }
    }

    func deleteAll() {
        lock.withLock { _ in
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}

/// Test and preview storage.
final class InMemoryClipboardHistoryStorage: ClipboardHistoryStorage {
    private let items = Mutex<[ClipboardItem]>([])

    init(initial: [ClipboardItem] = []) {
        items.withLock { $0 = initial }
    }

    func load() -> [ClipboardItem] { items.withLock { $0 } }
    func save(_ newItems: [ClipboardItem]) { items.withLock { $0 = newItems } }
    func deleteAll() { items.withLock { $0 = [] } }
}
