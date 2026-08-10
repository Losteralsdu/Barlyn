import Foundation

/// Failures raised while sampling a system metric.
///
/// Deliberately an enum rather than a general-purpose error box: metric readings are shown to
/// the user as "unavailable" with a reason, so the reason set has to be closed and exhaustive.
nonisolated enum MetricError: BarlynError {
    /// The underlying hardware or OS build does not expose this metric at all.
    /// Example: fan speed on a fanless MacBook Air.
    case unsupportedOnThisHardware(detail: String)

    /// A mach/IOKit call returned a non-success status.
    case systemCallFailed(api: String, code: Int32)

    /// The call succeeded but returned a value outside any physically plausible range.
    /// Real SMC sensors return sentinel garbage for inactive channels, so this is a normal,
    /// expected outcome rather than a programming error.
    case implausibleValue(detail: String)

    /// The metric needs a permission the user has not granted.
    case permissionRequired(PermissionKind)

    /// Sampling took longer than the caller was willing to wait.
    case timedOut

    var userMessage: String {
        switch self {
        case .unsupportedOnThisHardware:
            "Not available on this Mac."
        case .systemCallFailed, .implausibleValue:
            "Couldn't read this value."
        case .permissionRequired(let kind):
            "Requires \(kind.displayName) access."
        case .timedOut:
            "Timed out while reading this value."
        }
    }

    var diagnosticDescription: String {
        switch self {
        case .unsupportedOnThisHardware(let detail):
            "unsupported on this hardware: \(detail)"
        case .systemCallFailed(let api, let code):
            "\(api) failed with status \(code)"
        case .implausibleValue(let detail):
            "implausible value: \(detail)"
        case .permissionRequired(let kind):
            "missing permission: \(kind.rawValue)"
        case .timedOut:
            "sampling timed out"
        }
    }

    var isActionable: Bool {
        if case .permissionRequired = self { return true }
        return false
    }
}
