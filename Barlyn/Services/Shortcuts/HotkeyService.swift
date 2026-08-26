import Carbon.HIToolbox
import Foundation
import OSLog
import Synchronization

/// Registers system-wide keyboard shortcuts.
///
/// Uses Carbon's `RegisterEventHotKey`. It is an old API, but it remains the only way to claim a
/// global shortcut that **requires no permission and consumes the event**. The modern-looking
/// alternative, `NSEvent.addGlobalMonitorForEvents`, needs Input Monitoring *and* cannot stop the
/// keystroke reaching the focused app — pressing the launcher shortcut would also type into
/// whatever the user had open. Verified working on macOS 26 / Apple Silicon.
///
/// **Conflict detection is only partial, and the gap matters.** Registering a combination another
/// Barlyn shortcut already holds returns `eventHotKeyExistsErr` and is reported. Registering one
/// that *macOS itself* owns — Command+Space for Spotlight, for instance — returns `noErr` and then
/// silently never fires, because the system handler wins. Carbon offers no way to detect that, so
/// the UI must not promise a shortcut works merely because registration succeeded.
@MainActor
final class HotkeyService {
    /// Names a registration so it can be replaced or removed.
    nonisolated struct HotkeyID: Hashable, Sendable {
        let rawValue: String
        init(_ rawValue: String) { self.rawValue = rawValue }

        static let quickLauncher = HotkeyID("launcher.toggle")
    }

    private struct Registration {
        let ref: EventHotKeyRef
        let combination: KeyCombination
    }

    private var registrations: [HotkeyID: Registration] = [:]
    /// Carbon identifies a hotkey by a UInt32; this maps back to our own ids.
    private var carbonIDs: [UInt32: HotkeyID] = [:]
    private var nextCarbonID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    init() {}

    /// Registers `combination`, replacing any previous registration under the same id.
    func register(
        _ combination: KeyCombination,
        for id: HotkeyID,
        handler: @escaping @MainActor () -> Void
    ) throws(HotkeyError) {
        guard combination.isValidGlobalHotkey else { throw .missingModifiers }

        // Replace rather than reject: changing a shortcut in Settings is the common path, and
        // the old registration must go first or the new one collides with it.
        unregister(id)
        installEventHandlerIfNeeded()

        let carbonID = nextCarbonID
        nextCarbonID += 1

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(combination.keyCode),
            combination.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: carbonID),
            GetEventDispatcherTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else {
            if status == eventHotKeyExistsErr {
                throw .alreadyRegistered(combination: combination.displayString)
            }
            throw .registrationFailed(status: status)
        }

        registrations[id] = Registration(ref: ref, combination: combination)
        carbonIDs[carbonID] = id
        Self.handlers.withLock { $0[carbonID] = handler }

        AppLog.shortcuts.notice(
            "Registered \(combination.displayString, privacy: .public) for \(id.rawValue, privacy: .public)"
        )
    }

    func unregister(_ id: HotkeyID) {
        guard let registration = registrations.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(registration.ref)
        if let carbonID = carbonIDs.first(where: { $0.value == id })?.key {
            carbonIDs.removeValue(forKey: carbonID)
            Self.handlers.withLock { $0.removeValue(forKey: carbonID) }
        }
    }

    func unregisterAll() {
        // `Array(...)` is required: `keys` is a live view over the dictionary `unregister`
        // mutates, and iterating it while removing entries is undefined behaviour.
        for id in Array(registrations.keys) { unregister(id) }
    }

    /// Do **not** rewrite this as `registrations[id]?.combination`.
    ///
    /// That one-liner miscompiles here (Swift 6.3.3, Debug/-Onone): on an empty dictionary it
    /// returns a non-nil `KeyCombination` full of raw memory, while `registrations[id] == nil`
    /// evaluates to `true` in the same function. `Registration` begins with an `EventHotKeyRef`
    /// (a non-nullable pointer), which `Optional` uses as its extra-inhabitant tag, and the
    /// optional-chained form reads the payload without honouring it. The explicit `guard` form
    /// is correct and is the reason this is three lines instead of one.
    func combination(for id: HotkeyID) -> KeyCombination? {
        guard let registration = registrations[id] else { return nil }
        return registration.combination
    }

    // MARK: - Carbon plumbing

    private static let signature = OSType(0x424C_594E) // 'BLYN'

    /// Carbon dispatches to a C function pointer, which cannot capture context, so handlers live
    /// in a process-wide table keyed by the Carbon hotkey id. The `Mutex` is what makes that
    /// table safe to touch from the callback.
    private static let handlers = Mutex<[UInt32: @MainActor () -> Void]>([:])

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, _ -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }

                guard let handler = HotkeyService.handlers.withLock({ $0[hotKeyID.id] }) else {
                    return noErr
                }
                // Carbon delivers on the main thread, but that is an assumption about an old API
                // rather than a guarantee we control, so the hop is explicit.
                MainActor.assumeIsolated { handler() }
                return noErr
            },
            1,
            &spec,
            nil,
            &eventHandler
        )
    }
}
