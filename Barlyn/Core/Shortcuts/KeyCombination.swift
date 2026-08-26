import Carbon.HIToolbox
import Foundation

/// A key plus its modifiers, as a persistable value.
///
/// Stored as a virtual key code rather than a character, because the code is layout-independent:
/// the physical key that is `Z` on QWERTY is `Y` on QWERTZ, and a shortcut should stay on the
/// same physical key when the user switches layout.
nonisolated struct KeyCombination: Codable, Hashable, Sendable {
    let keyCode: UInt16
    let modifiers: ModifierKeys

    init(keyCode: UInt16, modifiers: ModifierKeys) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// The launcher default. Option+Space avoids Command+Space, which Spotlight owns.
    static let optionSpace = KeyCombination(keyCode: UInt16(kVK_Space), modifiers: .option)

    /// Carbon's modifier bit field, which uses different constants from `NSEvent`.
    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    /// Menu-style rendering, e.g. `⌥Space`.
    var displayString: String { modifiers.displayString + Self.keyName(for: keyCode) }

    /// A combination with no modifier would fire while the user is typing anywhere in the
    /// system, so it is never valid for a global hotkey.
    var isValidGlobalHotkey: Bool { !modifiers.isEmpty }

    /// Names for keys whose code does not map to a printable character. Unlisted codes fall back
    /// to a numeric form rather than guessing a character from the current keyboard layout.
    private static func keyName(for code: UInt16) -> String {
        switch Int(code) {
        case kVK_Space: "Space"
        case kVK_Return: "Return"
        case kVK_Escape: "Escape"
        case kVK_Tab: "Tab"
        case kVK_Delete: "Delete"
        case kVK_LeftArrow: "←"
        case kVK_RightArrow: "→"
        case kVK_UpArrow: "↑"
        case kVK_DownArrow: "↓"
        case kVK_ANSI_A: "A"; case kVK_ANSI_B: "B"; case kVK_ANSI_C: "C"; case kVK_ANSI_D: "D"
        case kVK_ANSI_E: "E"; case kVK_ANSI_F: "F"; case kVK_ANSI_G: "G"; case kVK_ANSI_H: "H"
        case kVK_ANSI_I: "I"; case kVK_ANSI_J: "J"; case kVK_ANSI_K: "K"; case kVK_ANSI_L: "L"
        case kVK_ANSI_M: "M"; case kVK_ANSI_N: "N"; case kVK_ANSI_O: "O"; case kVK_ANSI_P: "P"
        case kVK_ANSI_Q: "Q"; case kVK_ANSI_R: "R"; case kVK_ANSI_S: "S"; case kVK_ANSI_T: "T"
        case kVK_ANSI_U: "U"; case kVK_ANSI_V: "V"; case kVK_ANSI_W: "W"; case kVK_ANSI_X: "X"
        case kVK_ANSI_Y: "Y"; case kVK_ANSI_Z: "Z"
        case kVK_ANSI_0: "0"; case kVK_ANSI_1: "1"; case kVK_ANSI_2: "2"; case kVK_ANSI_3: "3"
        case kVK_ANSI_4: "4"; case kVK_ANSI_5: "5"; case kVK_ANSI_6: "6"; case kVK_ANSI_7: "7"
        case kVK_ANSI_8: "8"; case kVK_ANSI_9: "9"
        default: "Key \(code)"
        }
    }
}

/// Modifier keys, in the canonical order macOS renders them.
nonisolated struct ModifierKeys: OptionSet, Codable, Hashable, Sendable {
    let rawValue: Int

    init(rawValue: Int) { self.rawValue = rawValue }

    static let control = ModifierKeys(rawValue: 1 << 0)
    static let option = ModifierKeys(rawValue: 1 << 1)
    static let shift = ModifierKeys(rawValue: 1 << 2)
    static let command = ModifierKeys(rawValue: 1 << 3)

    /// Order matches Apple's convention: ⌃⌥⇧⌘.
    var displayString: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }
}
