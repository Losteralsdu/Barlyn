import Foundation
import Testing
@testable import Barlyn

@Suite("Metric model")
struct MetricModelTests {

    @Test("Plausibility bounds reject sentinel values from undocumented sensors")
    func plausibilityBounds() {
        // The real SMC returns values like this for inactive channels; observed on an
        // Apple Silicon Mac, key TTPD reported -306783232.0.
        #expect(MetricValue.celsius(-306_783_232).isPlausible == false)
        #expect(MetricValue.celsius(.nan).isPlausible == false)
        #expect(MetricValue.celsius(1000).isPlausible == false)
        #expect(MetricValue.celsius(61).isPlausible)

        #expect(MetricValue.percent(-1).isPlausible == false)
        #expect(MetricValue.percent(101).isPlausible == false)
        #expect(MetricValue.percent(0).isPlausible)
        #expect(MetricValue.percent(100).isPlausible)

        // Watts are signed: discharge is negative, charge positive.
        #expect(MetricValue.watts(-4.8).isPlausible)
        #expect(MetricValue.watts(32.4).isPlausible)
    }

    @Test("Units without a physical bound accept any finite value")
    func unboundedUnits() {
        #expect(MetricUnit.bytes.plausibleRange == nil)
        #expect(MetricValue.bytes(25_769_803_776).isPlausible)
        #expect(MetricValue(.infinity, .bytes).isPlausible == false)
    }

    @Test("checked() downgrades an implausible value instead of publishing it")
    func checkedDowngrades() {
        let bad = MetricReading.checked(.celsius(9999), detail: "sensor XYZ0")
        #expect(bad.isAvailable == false)
        #expect(bad.value == nil)

        guard case .unavailable(.failed(let error)) = bad else {
            Issue.record("Expected a failed reading, got \(bad)")
            return
        }
        #expect(error == .implausibleValue(detail: "sensor XYZ0"))

        let good = MetricReading.checked(.celsius(55), detail: "sensor XYZ0")
        #expect(good.value == .celsius(55))
    }

    @Test("Descriptor interval is clamped into the supported range")
    func intervalClamping() {
        let tooFast = MetricDescriptor(
            id: MetricIdentifier("test.fast"), displayName: "Fast", shortName: "F",
            symbolName: "bolt", unit: .percent, category: .system,
            preferredInterval: .milliseconds(1), provenance: .publicAPI(api: "test")
        )
        #expect(tooFast.effectiveInterval == AppConfiguration.minimumSampleInterval)

        let tooSlow = MetricDescriptor(
            id: MetricIdentifier("test.slow"), displayName: "Slow", shortName: "S",
            symbolName: "tortoise", unit: .percent, category: .system,
            preferredInterval: .seconds(3600), provenance: .publicAPI(api: "test")
        )
        #expect(tooSlow.effectiveInterval == AppConfiguration.maximumSampleInterval)
    }

    @Test("Provenance distinguishes supported APIs from reverse-engineered ones")
    func provenanceHonesty() {
        let documented = MetricProvenance.publicAPI(api: "getloadavg(3)")
        #expect(documented.isFullySupported)
        #expect(documented.caveatText == nil)

        let inferred = MetricProvenance.undocumentedInterface(
            interface: "AppleSMC Tp0*",
            caveat: "Sensor mapping is inferred."
        )
        #expect(inferred.isFullySupported == false)
        #expect(inferred.caveatText != nil)
    }

    @Test("Readings survive a Codable round trip")
    func codableRoundTrip() throws {
        let original = MetricReading.available(
            MetricSnapshot(
                value: .percent(24),
                components: [MetricComponent(id: "user", label: "User", value: .percent(18))]
            )
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MetricReading.self, from: data)
        #expect(decoded.value == .percent(24))
        #expect(decoded.snapshot?.component("user")?.value == .percent(18))
    }
}
