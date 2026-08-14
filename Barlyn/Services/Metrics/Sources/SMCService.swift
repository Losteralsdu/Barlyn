import Foundation
import IOKit
import OSLog

/// Reads Apple's System Management Controller.
///
/// This is the only way to reach die temperatures, fan speeds and power rails on a Mac, and it is
/// entirely undocumented. Everything here follows three rules that keep an undocumented interface
/// from becoming a source of invented numbers:
///
/// 1. **Never hard-code a key table.** Key sets differ per chip generation and per model. Keys are
///    enumerated at runtime via `#KEY` + `kSMCGetKeyFromIndex` and classified by prefix.
/// 2. **Range-check every value.** Real hardware returns sentinel garbage for inactive channels —
///    key `TTPD` was observed returning -306783232.0 on the development machine.
/// 3. **Discover once.** Enumerating all keys costs two IOKit round trips each (~3500 keys on the
///    development machine). Discovery runs once; sampling only re-reads the selected sensors.
///
/// Requires an unsandboxed process: `IOServiceOpen` on `AppleSMC` is denied under App Sandbox
/// without a temporary-exception entitlement (see ADR-001).
actor SMCService {

    /// What a sensor is believed to measure.
    ///
    /// "Believed" is not hedging: these mappings are community consensus derived from
    /// observation, not Apple documentation. Only families we are reasonably confident about are
    /// classified; everything else stays `nil` and is never published.
    nonisolated enum SensorFamily: String, Sendable, Hashable {
        /// Apple Silicon performance-core cluster die sensors (`Tp…`).
        case cpuPerformanceCore
        /// Apple Silicon efficiency-core cluster die sensors (`Te…`), absent on some chips.
        case cpuEfficiencyCore
        /// Apple Silicon GPU cluster die sensors (`Tg…`).
        case gpu
        /// Intel CPU die/proximity sensors, retained for older hardware.
        case cpuIntel
        /// Fan tachometer, actual RPM (`F…Ac`).
        case fanSpeed
    }

    nonisolated struct Sensor: Sendable, Hashable {
        let key: String
        let family: SensorFamily
        let dataType: String
        let dataSize: UInt32
    }

    /// Owns the IOKit connection so it can be closed in a `deinit`.
    ///
    /// An `actor`'s own `deinit` is nonisolated and cannot touch isolated state, so the handle
    /// lives in a plain class instead. `@unchecked Sendable` is sound because every use goes
    /// through the enclosing actor, which serialises access.
    private final class Connection: @unchecked Sendable {
        let port: io_connect_t

        init?() {
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
            guard service != 0 else { return nil }
            defer { IOObjectRelease(service) }

            var port: io_connect_t = 0
            guard IOServiceOpen(service, mach_task_self_, 0, &port) == kIOReturnSuccess else { return nil }
            self.port = port
        }

        deinit { IOServiceClose(port) }
    }

    private var connection: Connection?
    private var didAttemptOpen = false
    private var discoveredSensors: [Sensor]?

    init() {}

    /// True when the SMC could be opened at all.
    func isAvailable() -> Bool { openConnection() != nil }

    /// Sensors of a given family, discovered on first use and cached thereafter.
    func sensors(in family: SensorFamily) -> [Sensor] {
        allSensors().filter { $0.family == family }
    }

    /// Reads every sensor in a family, silently dropping implausible readings.
    ///
    /// Dropping rather than reporting is correct here: an inactive channel returning a sentinel
    /// is normal hardware behaviour, not an error worth surfacing. If *every* sensor in a family
    /// is implausible the caller sees an empty array and reports the metric unavailable.
    func readTemperatures(in family: SensorFamily) -> [Double] {
        sensors(in: family).compactMap { sensor in
            guard let celsius = readDouble(sensor) else { return nil }
            return MetricValue.celsius(celsius).isPlausible ? celsius : nil
        }
    }

    // MARK: - Discovery

    private func allSensors() -> [Sensor] {
        if let discoveredSensors { return discoveredSensors }

        let clock = ContinuousClock()
        var found: [Sensor] = []
        let start = clock.now

        if let count = keyCount() {
            for index in 0..<count {
                guard let key = key(at: index) else { continue }
                guard let family = Self.family(for: key) else { continue }
                guard let info = keyInfo(for: key) else { continue }
                found.append(
                    Sensor(
                        key: key,
                        family: family,
                        dataType: Self.fourCharacterCode(info.dataType),
                        dataSize: info.dataSize
                    )
                )
            }
        }

        let elapsed = clock.now - start
        discoveredSensors = found
        AppLog.temperature.notice(
            "SMC discovery found \(found.count) usable sensors in \(elapsed.milliseconds) ms"
        )
        return found
    }

    /// Prefix classification. Deliberately conservative — an unrecognised prefix yields `nil`
    /// rather than a guess, so an unknown sensor is never published under a confident label.
    nonisolated private static func family(for key: String) -> SensorFamily? {
        guard key.count == 4 else { return nil }
        // Fan tachometers are `F<n>Ac`; `F0Mn`/`F0Mx`/`F0Tg` are limits and targets, not actuals.
        if key.hasPrefix("F"), key.hasSuffix("Ac") { return .fanSpeed }
        if key.hasPrefix("Tp") { return .cpuPerformanceCore }
        if key.hasPrefix("Te") { return .cpuEfficiencyCore }
        if key.hasPrefix("Tg") { return .gpu }
        // Intel: TC0D is die, TC0P proximity. Only these two exact keys, because other `TC…`
        // keys on Intel hardware mean unrelated things.
        if key == "TC0D" || key == "TC0P" { return .cpuIntel }
        return nil
    }

    // MARK: - SMC protocol

    private func openConnection() -> Connection? {
        if !didAttemptOpen {
            didAttemptOpen = true
            connection = Connection()
            if connection == nil {
                AppLog.temperature.error("Could not open AppleSMC; temperature metrics unavailable")
            }
        }
        return connection
    }

    private func call(_ input: inout SMCKeyData) -> SMCKeyData? {
        guard let connection = openConnection() else { return nil }
        var output = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.stride

        let result = IOConnectCallStructMethod(
            connection.port,
            UInt32(Self.kSMCHandleYPCEvent),
            &input,
            MemoryLayout<SMCKeyData>.stride,
            &output,
            &outputSize
        )
        guard result == kIOReturnSuccess, output.result == 0 else { return nil }
        return output
    }

    private func keyCount() -> UInt32? {
        guard let info = keyInfo(for: "#KEY") else { return nil }
        var input = SMCKeyData()
        input.key = Self.fourCharacterCode("#KEY")
        input.data8 = Self.kSMCReadKey
        input.keyInfo = info
        guard let output = call(&input) else { return nil }

        return withUnsafeBytes(of: output.bytes) { raw in
            UInt32(raw[0]) << 24 | UInt32(raw[1]) << 16 | UInt32(raw[2]) << 8 | UInt32(raw[3])
        }
    }

    private func key(at index: UInt32) -> String? {
        var input = SMCKeyData()
        input.data8 = Self.kSMCGetKeyFromIndex
        input.data32 = index
        guard let output = call(&input) else { return nil }
        return Self.fourCharacterCode(output.key)
    }

    private func keyInfo(for key: String) -> SMCKeyInfoData? {
        var input = SMCKeyData()
        input.key = Self.fourCharacterCode(key)
        input.data8 = Self.kSMCGetKeyInfo
        return call(&input)?.keyInfo
    }

    /// Reads a sensor and decodes it to a `Double`, or `nil` if the type is not one we decode.
    private func readDouble(_ sensor: Sensor) -> Double? {
        var input = SMCKeyData()
        input.key = Self.fourCharacterCode(sensor.key)
        input.data8 = Self.kSMCReadKey
        input.keyInfo = SMCKeyInfoData(
            dataSize: sensor.dataSize,
            dataType: Self.fourCharacterCode(sensor.dataType),
            dataAttributes: 0
        )
        guard let output = call(&input) else { return nil }

        return withUnsafeBytes(of: output.bytes) { raw -> Double? in
            switch sensor.dataType {
            case "flt ":
                guard sensor.dataSize == 4 else { return nil }
                // Little-endian IEEE-754 single precision.
                let bits = UInt32(raw[0]) | UInt32(raw[1]) << 8 | UInt32(raw[2]) << 16 | UInt32(raw[3]) << 24
                return Double(Float(bitPattern: bits))
            case "sp78":
                // Intel-era fixed point: signed 8.8, big-endian.
                guard sensor.dataSize == 2 else { return nil }
                let bits = UInt16(raw[0]) << 8 | UInt16(raw[1])
                return Double(Int16(bitPattern: bits)) / 256.0
            default:
                return nil
            }
        }
    }

    // MARK: - Constants and helpers

    private static let kSMCHandleYPCEvent = 2
    private static let kSMCReadKey: UInt8 = 5
    private static let kSMCGetKeyFromIndex: UInt8 = 8
    private static let kSMCGetKeyInfo: UInt8 = 9

    nonisolated private static func fourCharacterCode(_ string: String) -> UInt32 {
        string.utf8.reduce(UInt32(0)) { ($0 << 8) + UInt32($1) }
    }

    nonisolated private static func fourCharacterCode(_ value: UInt32) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF),
        ]
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }
}

// MARK: - SMC wire format
//
// Layout must match the AppleSMC user client exactly; `SMCKeyData` is 80 bytes. A test asserts
// this, because a silent layout change would make every reading garbage rather than fail loudly.

nonisolated struct SMCVersion: Sendable {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

nonisolated struct SMCPLimitData: Sendable {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

nonisolated struct SMCKeyInfoData: Sendable {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

nonisolated struct SMCKeyData: Sendable {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )
}

nonisolated extension Duration {
    /// Whole milliseconds, for log lines.
    var milliseconds: Int64 {
        let (seconds, attoseconds) = components
        return seconds * 1_000 + attoseconds / 1_000_000_000_000_000
    }
}
