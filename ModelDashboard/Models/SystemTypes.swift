import Foundation

// MARK: - Memory

struct SystemMemoryInfo: Sendable {
    let totalBytes: UInt64
    let wiredBytes: UInt64
    let activeBytes: UInt64
    let inactiveBytes: UInt64
    let compressedBytes: UInt64
    let freeBytes: UInt64

    var totalGB: Double { Double(totalBytes) / 1_073_741_824 }
    var wiredGB: Double { Double(wiredBytes) / 1_073_741_824 }
    var activeGB: Double { Double(activeBytes) / 1_073_741_824 }
    var inactiveGB: Double { Double(inactiveBytes) / 1_073_741_824 }
    var compressedGB: Double { Double(compressedBytes) / 1_073_741_824 }
    var freeGB: Double { Double(freeBytes) / 1_073_741_824 }

    static let zero = SystemMemoryInfo(totalBytes: 0, wiredBytes: 0, activeBytes: 0, inactiveBytes: 0, compressedBytes: 0, freeBytes: 0)
}

// MARK: - Memory breakdown by category

struct MemoryBreakdown: Sendable {
    var modelMemory: UInt64 = 0
    var appMemory: UInt64 = 0
    var systemMemory: UInt64 = 0
    var cacheMemory: UInt64 = 0  // inactive
    var freeMemory: UInt64 = 0

    var modelGB: Double { Double(modelMemory) / 1_073_741_824 }
    var appGB: Double { Double(appMemory) / 1_073_741_824 }
    var systemGB: Double { Double(systemMemory) / 1_073_741_824 }
    var cacheGB: Double { Double(cacheMemory) / 1_073_741_824 }
    var freeGB: Double { Double(freeMemory) / 1_073_741_824 }
    var totalGB: Double { Double(modelMemory + appMemory + systemMemory + cacheMemory + freeMemory) / 1_073_741_824 }
}

// MARK: - CPU

struct CPUCoreUsage: Identifiable, Sendable {
    let id: Int  // core index
    let usage: Double  // 0.0 - 1.0
    let isPerformance: Bool  // P-core vs E-core
}

struct CPUUsageInfo: Sendable {
    let cores: [CPUCoreUsage]
    let pCoreAverage: Double
    let eCoreAverage: Double
    let overallAverage: Double

    static let zero = CPUUsageInfo(cores: [], pCoreAverage: 0, eCoreAverage: 0, overallAverage: 0)
}

// MARK: - GPU

struct GPUMetrics: Sendable {
    let utilizationPercent: Double  // 0-100
    let powerWatts: Double
    let activePState: Int           // highest active P-state index (0=off, higher=faster)
    let pStateDistribution: [PStateSlice]  // time spent in each P-state

    struct PStateSlice: Identifiable, Sendable {
        let id: Int       // P-state index
        let label: String // e.g. "P3", "OFF"
        let fraction: Double  // 0.0 - 1.0 of total time
    }

    static let zero = GPUMetrics(utilizationPercent: 0, powerWatts: 0, activePState: 0, pStateDistribution: [])
    static let unavailable = GPUMetrics(utilizationPercent: -1, powerWatts: -1, activePState: 0, pStateDistribution: [])

    var isAvailable: Bool { utilizationPercent >= 0 }
}

// MARK: - Temperature

struct TempStats: Sendable {
    let avg: Double
    let p90: Double
    let max: Double
}

struct TemperatureReadings: Sendable {
    var cpuTemp: TempStats?
    var gpuTemp: TempStats?
    var ssdTemp: Double?
    var ambientTemp: Double?
    var totalPowerW: Double?

    static let zero = TemperatureReadings()

    /// Compute avg / P90 / max from a list of sensor readings.
    static func stats(from values: [Double]) -> TempStats? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let avg = sorted.reduce(0, +) / Double(sorted.count)
        let p90Index = min(sorted.count - 1, Int(Double(sorted.count) * 0.9))
        return TempStats(avg: avg, p90: sorted[p90Index], max: sorted.last!)
    }
}

// MARK: - Throttle

struct ThrottleInfo: Sendable {
    /// macOS thermal state: 0=nominal, 1=fair, 2=serious, 3=critical
    var thermalState: Int = 0
    /// GPU: weighted average P-state as fraction of max P-state (1.0 = full speed)
    var gpuFreqRatio: Double = 1.0
    /// GPU: highest active P-state index seen this sample
    var gpuActivePState: Int = 0
    /// GPU: max possible P-state (from boost controller or observed)
    var gpuMaxPState: Int = 1
    /// CPU: fraction of P-core clusters that are active (1.0 = all active)
    var cpuClusterRatio: Double = 1.0
    /// Whether CLTM is actively limiting GPU
    var gpuCLTMActive: Bool = false

    var isThrottled: Bool { thermalState > 0 || gpuFreqRatio < 0.95 || cpuClusterRatio < 1.0 }

    var thermalStateLabel: String {
        switch thermalState {
        case 0: "Nominal"
        case 1: "Fair"
        case 2: "Serious"
        case 3: "Critical"
        default: "Unknown"
        }
    }

    static let nominal = ThrottleInfo()
}

// MARK: - Network I/O

struct NetworkIO: Sendable {
    let bytesInPerSec: UInt64
    let bytesOutPerSec: UInt64

    var inMBps: Double { Double(bytesInPerSec) / 1_048_576 }
    var outMBps: Double { Double(bytesOutPerSec) / 1_048_576 }

    static let zero = NetworkIO(bytesInPerSec: 0, bytesOutPerSec: 0)
}

// MARK: - Disk I/O

struct DiskIO: Sendable {
    let readBytesPerSec: UInt64
    let writeBytesPerSec: UInt64

    var readMBps: Double { Double(readBytesPerSec) / 1_048_576 }
    var writeMBps: Double { Double(writeBytesPerSec) / 1_048_576 }

    static let zero = DiskIO(readBytesPerSec: 0, writeBytesPerSec: 0)
}

// MARK: - History ring buffer for sparklines

struct RingBuffer<T: Sendable>: Sendable {
    private var storage: [T]
    private var writeIndex = 0
    private(set) var count = 0
    let capacity: Int

    init(capacity: Int, defaultValue: T) {
        self.capacity = capacity
        self.storage = Array(repeating: defaultValue, count: capacity)
    }

    mutating func append(_ value: T) {
        storage[writeIndex] = value
        writeIndex = (writeIndex + 1) % capacity
        if count < capacity { count += 1 }
    }

    /// Returns values in chronological order (oldest first).
    var values: [T] {
        if count < capacity {
            return Array(storage[0..<count])
        }
        return Array(storage[writeIndex..<capacity]) + Array(storage[0..<writeIndex])
    }
}
