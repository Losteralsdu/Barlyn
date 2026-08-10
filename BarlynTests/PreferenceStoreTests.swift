import Foundation
import Testing
@testable import Barlyn

@Suite("Preference store")
@MainActor
struct PreferenceStoreTests {

    private func makeStore() -> (PreferenceStore, InMemoryPreferenceStorage) {
        let storage = InMemoryPreferenceStorage()
        return (PreferenceStore(storage: storage), storage)
    }

    @Test("Unset preferences return their declared default")
    func defaults() {
        let (store, _) = makeStore()
        #expect(store[PreferenceKeys.hasCompletedOnboarding] == false)
        #expect(store[PreferenceKeys.appearance] == .system)
        #expect(store[PreferenceKeys.menuBarMetrics] == [.cpuUsage, .memoryUsage])
    }

    @Test("Values round trip through storage")
    func roundTrip() {
        let (store, storage) = makeStore()

        store[PreferenceKeys.hasCompletedOnboarding] = true
        store[PreferenceKeys.appearance] = .dark
        store[PreferenceKeys.menuBarMetrics] = [.cpuTemperature, .batteryPower]

        #expect(store[PreferenceKeys.hasCompletedOnboarding])
        #expect(store[PreferenceKeys.appearance] == .dark)
        #expect(store[PreferenceKeys.menuBarMetrics] == [.cpuTemperature, .batteryPower])

        // A fresh store over the same storage must read the persisted values, proving the
        // in-memory cache is not what made the previous assertions pass.
        let reopened = PreferenceStore(storage: storage)
        #expect(reopened[PreferenceKeys.appearance] == .dark)
        #expect(reopened[PreferenceKeys.menuBarMetrics] == [.cpuTemperature, .batteryPower])
    }

    @Test("Corrupt stored data falls back to the default and clears the bad entry")
    func corruptDataRecovery() {
        let storage = InMemoryPreferenceStorage(
            initialValues: [PreferenceKeys.appearance.name: Data("not json".utf8)]
        )
        let store = PreferenceStore(storage: storage)

        #expect(store[PreferenceKeys.appearance] == .system)
        // The unreadable entry is removed so it cannot fail on every subsequent read.
        #expect(storage.data(forKey: PreferenceKeys.appearance.name) == nil)
    }

    @Test("Resetting a single key restores its default")
    func resetSingleKey() {
        let (store, _) = makeStore()
        store[PreferenceKeys.appearance] = .light
        store.reset(PreferenceKeys.appearance)
        #expect(store[PreferenceKeys.appearance] == .system)
    }

    @Test("Reset all clears every stored preference")
    func resetAll() {
        let (store, storage) = makeStore()
        store[PreferenceKeys.appearance] = .dark
        store[PreferenceKeys.hasCompletedOnboarding] = true

        store.resetAll()

        #expect(store[PreferenceKeys.appearance] == .system)
        #expect(store[PreferenceKeys.hasCompletedOnboarding] == false)
        #expect(storage.allKeys().isEmpty)
    }

    @Test("Metric identifiers persist as readable strings, not ordinals")
    func identifierEncodingIsStable() throws {
        // Encoding by position would silently remap every user's saved metric list whenever a
        // new metric is inserted. Assert the wire format is the raw string.
        let data = try JSONEncoder().encode([MetricIdentifier.cpuUsage])
        #expect(String(decoding: data, as: UTF8.self) == #"["cpu.usage"]"#)
    }
}
