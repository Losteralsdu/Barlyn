import Foundation

/// Failures raised by the preference and persistence layer.
nonisolated enum PersistenceError: BarlynError {
    case encodingFailed(key: String, underlying: String)
    case decodingFailed(key: String, underlying: String)

    var userMessage: String {
        switch self {
        case .encodingFailed: "Couldn't save this setting."
        case .decodingFailed: "A saved setting was unreadable and has been reset."
        }
    }

    var diagnosticDescription: String {
        switch self {
        case .encodingFailed(let key, let underlying):
            "encoding failed for key '\(key)': \(underlying)"
        case .decodingFailed(let key, let underlying):
            "decoding failed for key '\(key)': \(underlying)"
        }
    }
}
