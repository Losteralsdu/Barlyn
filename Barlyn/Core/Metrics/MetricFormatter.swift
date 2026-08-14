import Foundation

/// Renders metric values for display.
///
/// Centralised so that a new metric needs no display code at all, and so the same value formats
/// identically in the menu bar, dashboard and Quick Launcher.
///
/// The locale is injected rather than read from `Locale.current` at call time so tests are
/// deterministic regardless of the machine's region settings.
nonisolated struct MetricFormatter: Sendable {
    /// Menu bar space is tight; dashboard space is not.
    enum Style: Sendable {
        /// Terse, fixed-width-ish: `24%`, `61°C`, `-4.8W`.
        case compact
        /// Spaced and rounded for readability: `24 %`, `61 °C`, `−4.8 W`.
        case detailed
    }

    /// Shown wherever a value is unavailable. An em dash, never `0` or `N/A`.
    static let unavailablePlaceholder = "—"

    let locale: Locale

    init(locale: Locale = .autoupdatingCurrent) {
        self.locale = locale
    }

    func string(for reading: MetricReading, style: Style = .compact) -> String {
        guard let value = reading.value else { return Self.unavailablePlaceholder }
        return string(for: value, style: style)
    }

    func string(for value: MetricValue, style: Style = .compact) -> String {
        let separator = style == .compact ? "" : " "
        switch value.unit {
        case .percent:
            return number(value.magnitude, fractionDigits: 0) + separator + value.unit.symbol
        case .celsius:
            return number(value.magnitude, fractionDigits: 0) + separator + value.unit.symbol
        case .watts:
            // Sign is meaningful for battery power (negative = discharging), so it is always
            // shown, including a leading "+" while charging.
            return signedNumber(value.magnitude, fractionDigits: 1) + separator + value.unit.symbol
        case .volts, .amperes:
            return number(value.magnitude, fractionDigits: 2) + separator + value.unit.symbol
        case .thermalLevel:
            return ThermalPressureLevel(rawValue: Int(value.magnitude))?.displayName
                ?? Self.unavailablePlaceholder
        case .powerState:
            return BatteryState(rawValue: Int(value.magnitude))?.displayName
                ?? Self.unavailablePlaceholder
        case .bytes:
            return bytes(value.magnitude)
        case .bytesPerSecond:
            return bytes(value.magnitude) + "/s"
        case .hertz:
            return number(value.magnitude / 1_000_000_000, fractionDigits: 2) + separator + "GHz"
        case .revolutionsPerMinute:
            return number(value.magnitude, fractionDigits: 0) + separator + value.unit.symbol
        case .seconds:
            return duration(value.magnitude)
        case .count:
            return number(value.magnitude, fractionDigits: 0)
        }
    }

    /// `"17.2 GB / 24 GB"` style pairing, used by memory and storage cards.
    func string(for value: MetricValue, of total: MetricValue, style: Style = .detailed) -> String {
        "\(string(for: value, style: style)) / \(string(for: total, style: style))"
    }

    // MARK: - Primitives

    private func number(_ magnitude: Double, fractionDigits: Int) -> String {
        magnitude.formatted(
            .number.precision(.fractionLength(fractionDigits)).locale(locale)
        )
    }

    private func signedNumber(_ magnitude: Double, fractionDigits: Int) -> String {
        magnitude.formatted(
            .number
                .precision(.fractionLength(fractionDigits))
                .sign(strategy: .always(includingZero: false))
                .locale(locale)
        )
    }

    private func bytes(_ magnitude: Double) -> String {
        // Metric units (GB, not GiB) to match how macOS itself reports storage and memory.
        Int64(magnitude.rounded()).formatted(
            .byteCount(style: .memory, allowedUnits: [.mb, .gb, .tb], spellsOutZero: false)
            .locale(locale)
        )
    }

    private func duration(_ totalSeconds: Double) -> String {
        let seconds = Int(totalSeconds.rounded())
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}
