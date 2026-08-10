import Foundation
import OSLog

/// Typed, observable access to persisted settings.
///
/// Values are JSON-encoded uniformly rather than mapped onto `UserDefaults`' native types. That
/// costs a little on write and buys one code path for primitives, enums and structs alike —
/// worth it because settings are written rarely and read from a warm in-memory cache.
///
/// Observation note: `@Observable` tracks the whole `cache` dictionary, so writing any preference
/// invalidates views reading any other. Acceptable given settings change at human speed; revisit
/// only if a high-frequency value ever ends up here (it should not — live metrics go through
/// `MetricSampler`, not preferences).
@MainActor
@Observable
final class PreferenceStore {
    private let storage: any PreferenceStorage
    private var cache: [String: any Sendable] = [:]

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(storage: any PreferenceStorage) {
        self.storage = storage
    }

    subscript<Value>(key: PreferenceKey<Value>) -> Value {
        get { value(for: key) }
        set { setValue(newValue, for: key) }
    }

    func value<Value>(for key: PreferenceKey<Value>) -> Value {
        if let cached = cache[key.name] as? Value { return cached }

        guard let data = storage.data(forKey: key.name) else {
            return key.defaultValue
        }

        do {
            let decoded = try decoder.decode(Value.self, from: data)
            cache[key.name] = decoded
            return decoded
        } catch {
            // A stored value that no longer decodes means the schema changed or the domain was
            // corrupted. Falling back to the default is right, but silently swallowing it is not:
            // drop the bad entry so it stops failing on every read, and record why.
            let persistenceError = PersistenceError.decodingFailed(
                key: key.name,
                underlying: String(describing: error)
            )
            AppLog.persistence.error("\(persistenceError.diagnosticDescription, privacy: .public)")
            storage.setData(nil, forKey: key.name)
            return key.defaultValue
        }
    }

    func setValue<Value>(_ newValue: Value, for key: PreferenceKey<Value>) {
        do {
            let data = try encoder.encode(newValue)
            storage.setData(data, forKey: key.name)
            cache[key.name] = newValue
        } catch {
            let persistenceError = PersistenceError.encodingFailed(
                key: key.name,
                underlying: String(describing: error)
            )
            AppLog.persistence.error("\(persistenceError.diagnosticDescription, privacy: .public)")
        }
    }

    /// Restores a single preference to its default.
    func reset<Value>(_ key: PreferenceKey<Value>) {
        storage.setData(nil, forKey: key.name)
        cache.removeValue(forKey: key.name)
    }

    /// Restores every Barlyn preference to its default. Exposed in Settings › Advanced.
    func resetAll() {
        for key in storage.allKeys() {
            storage.setData(nil, forKey: key)
        }
        cache.removeAll()
        AppLog.persistence.notice("All preferences reset to defaults")
    }
}
