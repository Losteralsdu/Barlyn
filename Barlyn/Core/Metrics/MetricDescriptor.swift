import Foundation

/// Grouping used by the dashboard and Settings to lay metrics out.
nonisolated enum MetricCategory: String, Sendable, Hashable, Codable, CaseIterable {
    case processor
    case memory
    case power
    case thermal
    case storage
    case network
    case system

    /// Default ordering for UI that has no user-defined layout yet.
    ///
    /// Exists because provider registration order is an implementation detail — providers that
    /// need slow hardware probing register in a later wave (ADR-008) and would otherwise sort
    /// to the bottom purely because they were slow to confirm.
    var sortIndex: Int {
        switch self {
        case .processor: 0
        case .memory: 1
        case .thermal: 2
        case .power: 3
        case .storage: 4
        case .network: 5
        case .system: 6
        }
    }

    var displayName: String {
        switch self {
        case .processor: "Processor"
        case .memory: "Memory"
        case .power: "Power"
        case .thermal: "Thermal"
        case .storage: "Storage"
        case .network: "Network"
        case .system: "System"
        }
    }
}

/// Where a metric's number actually comes from.
///
/// This exists because of a specific hazard: several interesting Mac metrics (die temperature,
/// fan speed, per-rail power) are only reachable through interfaces Apple does not document.
/// Those values are real, but their *interpretation* is reverse-engineered community consensus,
/// and that uncertainty must survive all the way to the UI instead of being flattened into a
/// confident-looking number. Views can badge or footnote anything that is not `.publicAPI`.
nonisolated enum MetricProvenance: Sendable, Hashable, Codable {
    /// Documented, supported Apple API.
    case publicAPI(api: String)
    /// Readable but undocumented system interface; naming/meaning is inferred, not guaranteed.
    case undocumentedInterface(interface: String, caveat: String)
    /// Computed from other metrics rather than measured directly.
    case derived(from: String)

    var isFullySupported: Bool {
        if case .publicAPI = self { return true }
        return false
    }

    /// Short note suitable for a UI footnote or tooltip. `nil` when no caveat applies.
    var caveatText: String? {
        switch self {
        case .publicAPI: nil
        case .undocumentedInterface(_, let caveat): caveat
        case .derived(let source): "Calculated from \(source)."
        }
    }

    var diagnosticDescription: String {
        switch self {
        case .publicAPI(let api): "public API: \(api)"
        case .undocumentedInterface(let interface, _): "undocumented interface: \(interface)"
        case .derived(let source): "derived from: \(source)"
        }
    }
}

/// Everything the UI needs to know about a metric without knowing how it is measured.
///
/// A new metric becomes displayable in the menu bar, dashboard and Quick Launcher by supplying
/// one of these plus a `read()` implementation. No UI switch statements per metric.
nonisolated struct MetricDescriptor: Sendable, Hashable, Codable, Identifiable {
    let id: MetricIdentifier
    /// Full name, e.g. "Processor Usage".
    let displayName: String
    /// Menu bar label, e.g. "CPU". Kept short because menu bar width is scarce.
    let shortName: String
    /// SF Symbol name.
    let symbolName: String
    let unit: MetricUnit
    let category: MetricCategory
    /// Cadence this metric is meaningful at. Clamped by `AppConfiguration` before use.
    let preferredInterval: Duration
    let provenance: MetricProvenance

    init(
        id: MetricIdentifier,
        displayName: String,
        shortName: String,
        symbolName: String,
        unit: MetricUnit,
        category: MetricCategory,
        preferredInterval: Duration = AppConfiguration.defaultSampleInterval,
        provenance: MetricProvenance
    ) {
        self.id = id
        self.displayName = displayName
        self.shortName = shortName
        self.symbolName = symbolName
        self.unit = unit
        self.category = category
        self.preferredInterval = preferredInterval
        self.provenance = provenance
    }

    var effectiveInterval: Duration { AppConfiguration.clampSampleInterval(preferredInterval) }
}
