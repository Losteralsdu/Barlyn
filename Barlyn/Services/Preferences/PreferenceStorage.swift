import Foundation
import Synchronization

/// Raw key-value backing for preferences.
///
/// Deliberately narrow: everything above this layer works with typed `PreferenceKey`s, and this
/// protocol exists so tests can run against an in-memory store without touching the user's real
/// `UserDefaults` domain.
nonisolated protocol PreferenceStorage: AnyObject, Sendable {
    func data(forKey key: String) -> Data?
    func setData(_ data: Data?, forKey key: String)
    /// All keys currently held. Used by "reset all settings".
    func allKeys() -> [String]
}

/// Production storage.
final class UserDefaultsPreferenceStorage: PreferenceStorage {
    /// `UserDefaults` is documented as thread-safe but is not annotated `Sendable`, so the
    /// guarantee has to be asserted manually. No additional locking is needed here.
    private nonisolated(unsafe) let defaults: UserDefaults
    /// Namespacing keeps Barlyn's entries identifiable in the defaults domain and makes a
    /// wholesale reset possible without clobbering system-managed keys such as `NSWindow*`.
    private let prefix = "barlyn."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func data(forKey key: String) -> Data? {
        defaults.data(forKey: prefix + key)
    }

    func setData(_ data: Data?, forKey key: String) {
        if let data {
            defaults.set(data, forKey: prefix + key)
        } else {
            defaults.removeObject(forKey: prefix + key)
        }
    }

    func allKeys() -> [String] {
        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
    }
}

/// Test and preview storage.
final class InMemoryPreferenceStorage: PreferenceStorage {
    private let store = Mutex<[String: Data]>([:])

    init(initialValues: [String: Data] = [:]) {
        store.withLock { $0 = initialValues }
    }

    func data(forKey key: String) -> Data? {
        store.withLock { $0[key] }
    }

    func setData(_ data: Data?, forKey key: String) {
        store.withLock { $0[key] = data }
    }

    func allKeys() -> [String] {
        store.withLock { Array($0.keys) }
    }
}
