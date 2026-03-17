import Foundation
import IOKit

// MARK: - SMC temperature reader

/// SMC key data structure for AppleSMC communication.
private struct SMCKeyData {
    struct vers_t { var major: UInt8 = 0; var minor: UInt8 = 0; var build: UInt8 = 0; var reserved: UInt8 = 0; var release: UInt16 = 0 }
    struct pLimitData { var version: UInt16 = 0; var length: UInt16 = 0; var cpuPLimit: UInt32 = 0; var gpuPLimit: UInt32 = 0; var memPLimit: UInt32 = 0 }
    struct keyInfo_t { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0 }
    var key: UInt32 = 0
    var vers: vers_t = vers_t()
    var pLimitData: pLimitData = pLimitData()
    var keyInfo: keyInfo_t = keyInfo_t()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8) =
        (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

private let KERNEL_INDEX_SMC: UInt32 = 2
private let SMC_CMD_READ_KEYINFO: UInt8 = 9
private let SMC_CMD_READ_BYTES: UInt8 = 5
private let SMC_CMD_GET_KEY_FROM_INDEX: UInt8 = 8

private func fourCC(_ s: String) -> UInt32 {
    var r: UInt32 = 0
    for c in s.utf8 { r = (r << 8) | UInt32(c) }
    return r
}

private func ccStr(_ v: UInt32) -> String {
    String(bytes: [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF),
                   UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)], encoding: .ascii) ?? "????"
}

// MARK: - HID private API via @_silgen_name (for SSD + ambient)

@_silgen_name("IOHIDEventSystemClientCreate")
private func HIDClientCreate(_ allocator: CFAllocator?) -> CFTypeRef?

@_silgen_name("IOHIDEventSystemClientCopyServices")
private func HIDClientCopyServices(_ client: CFTypeRef) -> CFArray?

@_silgen_name("IOHIDServiceClientCopyProperty")
private func HIDServiceCopyProperty(_ service: CFTypeRef, _ key: CFString) -> CFTypeRef?

@_silgen_name("IOHIDServiceClientCopyEvent")
private func HIDServiceCopyEvent(_ service: CFTypeRef, _ type: Int64, _ a: Int32, _ b: Int64) -> CFTypeRef?

@_silgen_name("IOHIDEventGetFloatValue")
private func HIDEventGetFloatValue(_ event: CFTypeRef, _ field: UInt32) -> Double

private let kHIDTempType: Int64 = 15
private let kHIDTempField: UInt32 = 15 << 16

/// Reads hardware temperatures via SMC (CPU/GPU die) and HID (SSD/ambient).
/// SMC gives accurate die temperatures matching what Stats.app shows.
final class TemperatureReader: @unchecked Sendable {

    private var smcConnection: io_connect_t = 0
    private var smcAvailable = false
    /// Cached list of SMC temperature key codes, discovered once at init.
    private var cpuKeysCodes: [UInt32] = []
    private var gpuKeysCodes: [UInt32] = []

    init() {
        setupSMC()
    }

    deinit {
        if smcAvailable {
            IOServiceClose(smcConnection)
        }
    }

    func read() -> TemperatureReadings {
        var readings = TemperatureReadings()

        // SMC: CPU and GPU die temperatures → avg / P90 / max
        if smcAvailable {
            var cpuValues: [Double] = []
            for code in cpuKeysCodes {
                if let t = readSMCKey(code), t > 10 { cpuValues.append(t) }
            }
            var gpuValues: [Double] = []
            for code in gpuKeysCodes {
                if let t = readSMCKey(code), t > 10 { gpuValues.append(t) }
            }
            readings.cpuTemp = TemperatureReadings.stats(from: cpuValues)
            readings.gpuTemp = TemperatureReadings.stats(from: gpuValues)
        }

        // HID: SSD and ambient (SMC doesn't have good ambient data)
        readHID(&readings)

        return readings
    }

    // MARK: - SMC setup

    private func setupSMC() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        let kr = IOServiceOpen(service, mach_task_self_, KERNEL_INDEX_SMC, &smcConnection)
        guard kr == kIOReturnSuccess, smcConnection != 0 else { return }
        smcAvailable = true

        // Discover temperature keys
        discoverTempKeys()
    }

    private func discoverTempKeys() {
        let count = getKeyCount()

        for i in 0..<count {
            guard let keyCode = getKeyAtIndex(i) else { continue }
            let name = ccStr(keyCode)

            // CPU: Tp* keys (P-core die temps)
            if name.hasPrefix("Tp") {
                if let val = readSMCKey(keyCode), val > 10, val < 120, val != 40.0 {
                    cpuKeysCodes.append(keyCode)
                }
            }
            // GPU: Tg* keys (GPU die temps)
            else if name.hasPrefix("Tg") {
                if let val = readSMCKey(keyCode), val > 10, val < 120 {
                    gpuKeysCodes.append(keyCode)
                }
            }
        }
    }

    // MARK: - SMC communication

    private func smcCall(_ input: inout SMCKeyData) -> SMCKeyData? {
        var output = SMCKeyData()
        var sz = MemoryLayout<SMCKeyData>.size
        let r = IOConnectCallStructMethod(smcConnection, UInt32(KERNEL_INDEX_SMC),
                                          &input, sz, &output, &sz)
        return r == kIOReturnSuccess ? output : nil
    }

    private func getKeyCount() -> UInt32 {
        var input = SMCKeyData()
        input.key = fourCC("#KEY")
        input.data8 = SMC_CMD_READ_KEYINFO
        guard let info = smcCall(&input) else { return 0 }
        input.keyInfo.dataSize = info.keyInfo.dataSize
        input.data8 = SMC_CMD_READ_BYTES
        guard let data = smcCall(&input) else { return 0 }
        return (UInt32(data.bytes.0) << 24) | (UInt32(data.bytes.1) << 16) |
               (UInt32(data.bytes.2) << 8) | UInt32(data.bytes.3)
    }

    private func getKeyAtIndex(_ idx: UInt32) -> UInt32? {
        var input = SMCKeyData()
        input.data8 = SMC_CMD_GET_KEY_FROM_INDEX
        input.data32 = idx
        guard let output = smcCall(&input) else { return nil }
        return output.key
    }

    private func readSMCKey(_ keyCode: UInt32) -> Double? {
        var input = SMCKeyData()
        input.key = keyCode
        input.data8 = SMC_CMD_READ_KEYINFO
        guard let info = smcCall(&input) else { return nil }

        let dataSize = info.keyInfo.dataSize
        let dataType = info.keyInfo.dataType
        guard dataSize > 0 else { return nil }

        input.keyInfo.dataSize = dataSize
        input.data8 = SMC_CMD_READ_BYTES
        guard let data = smcCall(&input) else { return nil }

        let typeStr = ccStr(dataType)

        // flt  — 32-bit float (most common on Apple Silicon)
        if typeStr == "flt " && dataSize == 4 {
            var f: Float = 0
            withUnsafeMutableBytes(of: &f) { p in
                p[0] = data.bytes.0; p[1] = data.bytes.1
                p[2] = data.bytes.2; p[3] = data.bytes.3
            }
            return Double(f)
        }

        // sp78 — signed fixed-point 7.8
        if typeStr == "sp78" && dataSize >= 2 {
            let raw = (Int16(data.bytes.0) << 8) | Int16(data.bytes.1)
            return Double(raw) / 256.0
        }

        return nil
    }

    // MARK: - HID (SSD + ambient only)

    private func readHID(_ readings: inout TemperatureReadings) {
        guard let client = HIDClientCreate(kCFAllocatorDefault),
              let services = HIDClientCopyServices(client) as? [CFTypeRef] else { return }
        // HIDClientCreate follows CF Create Rule (+1 retained).
        // ARC manages the `client` AnyObject reference — it will be released
        // when this scope exits, balancing the +1 from Create.

        var lowestDev: Double = 200

        for service in services {
            guard let productRef = HIDServiceCopyProperty(service, "Product" as CFString),
                  let product = productRef as? String else { continue }
            guard let event = HIDServiceCopyEvent(service, kHIDTempType, 0, 0) else { continue }
            let temp = HIDEventGetFloatValue(event, kHIDTempField)
            guard temp > 0 && temp < 150 else { continue }

            let lower = product.lowercased()

            if lower.contains("nand") || lower.contains("ssd") {
                readings.ssdTemp = temp
            } else if lower.contains("tdev3") || lower.contains("tdev4") ||
                      lower.contains("tdev5") || lower.contains("tdev8") {
                lowestDev = min(lowestDev, temp)
            }
        }

        if lowestDev < 200 { readings.ambientTemp = lowestDev }
    }
}
