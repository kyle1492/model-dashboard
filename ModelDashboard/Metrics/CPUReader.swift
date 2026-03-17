import Foundation
import Darwin

/// Reads per-core CPU usage via host_processor_info().
/// Distinguishes P-cores (performance) and E-cores (efficiency) on Apple Silicon.
final class CPUReader: Sendable {
    // M4 Max: 12 P-cores + 4 E-cores = 16 total
    // P-cores are listed first by macOS
    private let pCoreCount: Int
    private let eCoreCount: Int

    // Previous tick values for delta calculation
    private struct CoreTicks: Sendable {
        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        var nice: UInt64 = 0
    }

    // Use a lock for thread-safe state. nonisolated(unsafe) to satisfy Sendable.
    nonisolated(unsafe) private var previousTicks: [CoreTicks] = []
    nonisolated(unsafe) private let lock = NSLock()

    init() {
        // Detect core topology via sysctl
        let pCount = Self.sysctlInt("hw.perflevel0.logicalcpu") ?? 12
        let eCount = Self.sysctlInt("hw.perflevel1.logicalcpu") ?? 4
        self.pCoreCount = pCount
        self.eCoreCount = eCount
    }

    func read() -> CPUUsageInfo {
        var numCPUsU: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUsU,
            &cpuInfo,
            &numCPUInfo
        )

        guard result == KERN_SUCCESS, let info = cpuInfo else {
            return .zero
        }

        let numCPUs = Int(numCPUsU)
        var cores: [CPUCoreUsage] = []

        lock.lock()
        if previousTicks.isEmpty {
            previousTicks = Array(repeating: CoreTicks(), count: numCPUs)
        }

        for i in 0..<numCPUs {
            let base = Int32(i) * Int32(CPU_STATE_MAX)
            let user = UInt64(info[Int(base + Int32(CPU_STATE_USER))])
            let system = UInt64(info[Int(base + Int32(CPU_STATE_SYSTEM))])
            let idle = UInt64(info[Int(base + Int32(CPU_STATE_IDLE))])
            let nice = UInt64(info[Int(base + Int32(CPU_STATE_NICE))])

            let prev = previousTicks[i]
            let dUser = user - prev.user
            let dSystem = system - prev.system
            let dIdle = idle - prev.idle
            let dNice = nice - prev.nice

            let total = dUser + dSystem + dIdle + dNice
            let usage = total > 0 ? Double(dUser + dSystem + dNice) / Double(total) : 0

            let isP = i < pCoreCount
            cores.append(CPUCoreUsage(id: i, usage: min(1, max(0, usage)), isPerformance: isP))

            previousTicks[i] = CoreTicks(user: user, system: system, idle: idle, nice: nice)
        }
        lock.unlock()

        // Deallocate
        let deallocSize = vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.size)
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), deallocSize)

        let pCores = cores.filter(\.isPerformance)
        let eCores = cores.filter { !$0.isPerformance }

        let pAvg = pCores.isEmpty ? 0 : pCores.map(\.usage).reduce(0, +) / Double(pCores.count)
        let eAvg = eCores.isEmpty ? 0 : eCores.map(\.usage).reduce(0, +) / Double(eCores.count)
        let overall = cores.isEmpty ? 0 : cores.map(\.usage).reduce(0, +) / Double(cores.count)

        return CPUUsageInfo(
            cores: cores,
            pCoreAverage: pAvg,
            eCoreAverage: eAvg,
            overallAverage: overall
        )
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int = 0
        var size = MemoryLayout<Int>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}
