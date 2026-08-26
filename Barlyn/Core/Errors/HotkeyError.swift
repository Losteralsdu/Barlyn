import Foundation

/// Failures from global shortcut registration.
nonisolated enum HotkeyError: BarlynError {
    /// Another shortcut in this process already owns the combination. Carbon reports this as
    /// `eventHotKeyExistsErr`, so it is the one conflict class that can be detected reliably.
    case alreadyRegistered(combination: String)
    /// A combination with no modifiers would fire while typing anywhere on the system.
    case missingModifiers
    case registrationFailed(status: Int32)

    var userMessage: String {
        switch self {
        case .alreadyRegistered(let combination):
            "\(combination) is already used by another Barlyn shortcut."
        case .missingModifiers:
            "A global shortcut needs at least one modifier key."
        case .registrationFailed:
            "macOS refused to register this shortcut."
        }
    }

    var diagnosticDescription: String {
        switch self {
        case .alreadyRegistered(let combination): "hotkey already registered: \(combination)"
        case .missingModifiers: "hotkey has no modifiers"
        case .registrationFailed(let status): "RegisterEventHotKey failed with OSStatus \(status)"
        }
    }

    var isActionable: Bool { true }
}
