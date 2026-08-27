import Foundation

/// Failures from the clipboard history store.
nonisolated enum ClipboardError: BarlynError {
    case storageUnavailable(detail: String)
    case writeFailed(detail: String)

    var userMessage: String {
        switch self {
        case .storageUnavailable: "Clipboard history is unavailable."
        case .writeFailed: "Couldn't save clipboard history."
        }
    }

    /// Diagnostics describe the *failure*, never the clipboard entry involved. Clipboard contents
    /// must not reach the log at any level (§37).
    var diagnosticDescription: String {
        switch self {
        case .storageUnavailable(let detail): "clipboard storage unavailable: \(detail)"
        case .writeFailed(let detail): "clipboard write failed: \(detail)"
        }
    }
}
