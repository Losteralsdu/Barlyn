import Foundation
import Testing
@testable import Barlyn

/// Locale is pinned so results do not depend on the developer's region settings.
@Suite("Metric formatting")
struct MetricFormatterTests {
    private let formatter = MetricFormatter(locale: Locale(identifier: "en_US_POSIX"))

    @Test("Compact style omits the space before the unit")
    func compactStyle() {
        #expect(formatter.string(for: .percent(24), style: .compact) == "24%")
        #expect(formatter.string(for: .celsius(61), style: .compact) == "61°C")
    }

    @Test("Detailed style separates magnitude and unit")
    func detailedStyle() {
        #expect(formatter.string(for: .percent(24), style: .detailed) == "24 %")
    }

    @Test("Wattage always carries an explicit sign")
    func signedWattage() {
        // Sign conveys charge direction, so "+32.4 W" must not collapse to "32.4 W".
        #expect(formatter.string(for: .watts(-4.8), style: .compact) == "-4.8W")
        #expect(formatter.string(for: .watts(32.4), style: .compact) == "+32.4W")
    }

    @Test("Unavailable readings render as an em dash, never as zero")
    func unavailablePlaceholder() {
        #expect(formatter.string(for: .notYetSampled) == "—")
        #expect(formatter.string(for: .unavailable(.failed(.timedOut))) == "—")
        #expect(
            formatter.string(for: .unavailable(.failed(.unsupportedOnThisHardware(detail: "no fan")))) == "—"
        )
    }

    @Test("Uptime renders in human units")
    func durationFormatting() {
        #expect(formatter.string(for: .seconds(90)) == "1m")
        #expect(formatter.string(for: .seconds(3_900)) == "1h 5m")
        #expect(formatter.string(for: .seconds(180_000)) == "2d 2h")
    }

    @Test("Paired values read as used-of-total")
    func pairedValues() {
        let used = MetricValue.bytes(18_400_000_000)
        let total = MetricValue.bytes(25_769_803_776)
        let text = formatter.string(for: used, of: total)
        #expect(text.contains("/"))
        #expect(text.contains("GB"))
    }
}
