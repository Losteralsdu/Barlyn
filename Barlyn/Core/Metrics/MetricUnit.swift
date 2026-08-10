import Foundation

/// Physical unit of a metric value.
///
/// The unit drives formatting everywhere (menu bar, dashboard, launcher) so that adding a
/// metric never requires touching display code — see `MetricFormatter`.
nonisolated enum MetricUnit: String, Sendable, Hashable, Codable, CaseIterable {
    case percent
    case celsius
    case watts
    case bytes
    case bytesPerSecond
    case hertz
    case revolutionsPerMinute
    case seconds
    /// Dimensionless count (processes, cycles, connections).
    case count

    /// Symbol appended to a formatted magnitude. Empty when the format style already carries
    /// the unit (bytes are rendered as "17.2 GB" by `ByteCountFormatStyle`).
    var symbol: String {
        switch self {
        case .percent: "%"
        case .celsius: "°C"
        case .watts: "W"
        case .bytes, .bytesPerSecond: ""
        case .hertz: "Hz"
        case .revolutionsPerMinute: "RPM"
        case .seconds: ""
        case .count: ""
        }
    }

    /// Range a physically meaningful reading must fall in, used to reject sentinel values that
    /// undocumented sensor interfaces return for inactive channels.
    /// `nil` means "no meaningful bound".
    var plausibleRange: ClosedRange<Double>? {
        switch self {
        case .percent: 0...100
        case .celsius: -40...150
        // Signed: negative is discharge, positive is charge.
        case .watts: -400...400
        case .revolutionsPerMinute: 0...20_000
        case .bytes, .bytesPerSecond, .hertz, .seconds, .count: nil
        }
    }
}
