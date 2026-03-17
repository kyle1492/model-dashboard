import Foundation

/// Reads GPU utilization and power via IOReport private API.
///
/// M3/M4 Max channel layout:
/// - GPU utilization: [GPU Stats/GPU Performance States] GPUPH — state residency (OFF vs P1..P15)
/// - GPU power: [Energy Model] GPU0, GPU CS0, GPU SRAM0, GPU CS SRAM0 — values in mW
final class IOReportReader: Sendable {

    nonisolated(unsafe) private var subscription: IOReportSubscriptionRef?
    nonisolated(unsafe) private var subscribedChannels: CFMutableDictionary?
    nonisolated(unsafe) private var previousSample: CFDictionary?
    nonisolated(unsafe) private let lock = NSLock()
    nonisolated(unsafe) private var available = false

    init() {
        setupSubscription()
    }

    var isAvailable: Bool { available }

    func read() -> GPUMetrics {
        guard available else { return .unavailable }

        lock.lock()
        defer { lock.unlock() }

        guard let sub = subscription,
              let channels = subscribedChannels else {
            return .unavailable
        }

        guard let currentSampleUnmanaged = IOReportCreateSamples(sub, channels, nil) else {
            return .unavailable
        }
        let currentSample = currentSampleUnmanaged.takeRetainedValue()

        defer { previousSample = currentSample }

        guard let prev = previousSample else {
            previousSample = currentSample
            return .zero
        }

        guard let deltaUnmanaged = IOReportCreateSamplesDelta(prev, currentSample, nil) else {
            return .zero
        }
        let delta = deltaUnmanaged.takeRetainedValue()

        var gpuOffResidency: Int64 = 0
        var gpuTotalResidency: Int64 = 0
        var foundGPUPH = false
        var pStates: [(index: Int, label: String, residency: Int64)] = []
        var highestActiveState = 0

        // GPU power: sum specific component channels (values in mW)
        var gpuPowerMW: Double = 0
        let gpuPowerChannels: Set<String> = ["GPU0", "GPU CS0", "GPU SRAM0", "GPU CS SRAM0"]

        IOReportIterate(delta) { channel in
            let group = (IOReportChannelGetGroup(channel)?.takeUnretainedValue()) as String? ?? ""
            let subgroup = (IOReportChannelGetSubGroup(channel)?.takeUnretainedValue()) as String? ?? ""
            let name = (IOReportChannelGetChannelName(channel)?.takeUnretainedValue()) as String? ?? ""

            // GPU Utilization: GPUPH in [GPU Stats/GPU Performance States]
            if group == "GPU Stats" && subgroup == "GPU Performance States" && name == "GPUPH" {
                let stateCount = IOReportStateGetCount(channel)
                if stateCount > 0 {
                    foundGPUPH = true
                    for s in 0..<stateCount {
                        let residency = IOReportStateGetResidency(channel, s)
                        let stateName = (IOReportStateGetNameForIndex(channel, s)?.takeUnretainedValue()) as String? ?? ""
                        gpuTotalResidency += residency
                        pStates.append((index: Int(s), label: stateName, residency: residency))
                        if stateName == "OFF" {
                            gpuOffResidency += residency
                        } else if residency > 0 {
                            highestActiveState = max(highestActiveState, Int(s))
                        }
                    }
                }
            }

            // GPU Power: specific Energy Model component channels (mW)
            if group == "Energy Model" && gpuPowerChannels.contains(name) {
                let value = IOReportSimpleGetIntegerValue(channel, 0)
                if value > 0 {
                    gpuPowerMW += Double(value)
                }
            }

            return 0
        }

        // Calculate utilization: active = total - OFF
        var utilization: Double = 0
        if foundGPUPH && gpuTotalResidency > 0 {
            let active = gpuTotalResidency - gpuOffResidency
            utilization = Double(active) / Double(gpuTotalResidency) * 100
        }

        let powerWatts = gpuPowerMW / 1000.0

        // Build P-state distribution (skip OFF state at index 0)
        let distribution: [GPUMetrics.PStateSlice] = pStates.compactMap { ps in
            guard gpuTotalResidency > 0 else { return nil }
            return GPUMetrics.PStateSlice(
                id: ps.index,
                label: ps.label,
                fraction: Double(ps.residency) / Double(gpuTotalResidency)
            )
        }

        return GPUMetrics(
            utilizationPercent: min(100, max(0, utilization)),
            powerWatts: powerWatts,
            activePState: highestActiveState,
            pStateDistribution: distribution
        )
    }

    // MARK: - Setup

    private func setupSubscription() {
        // Need both GPU Stats (utilization) and Energy Model (power)
        guard let gpuStatsUnmanaged = IOReportCopyChannelsInGroup("GPU Stats" as CFString, nil, 0, 0, 0) else {
            available = false
            return
        }
        let gpuStats = gpuStatsUnmanaged.takeRetainedValue()
        let merged = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, gpuStats)!

        // Add Energy Model channels for power
        if let energyUnmanaged = IOReportCopyChannelsInGroup("Energy Model" as CFString, nil, 0, 0, 0) {
            let energyChannels = energyUnmanaged.takeRetainedValue()
            let energyMutable = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, energyChannels)!
            IOReportMergeChannels(merged, energyMutable, nil)
        }

        var subbedChannelsUnmanaged: Unmanaged<CFMutableDictionary>?
        let sub = IOReportCreateSubscription(nil, merged, &subbedChannelsUnmanaged, 0, nil)

        if sub != nil, let subbed = subbedChannelsUnmanaged?.takeRetainedValue() {
            subscription = sub
            subscribedChannels = subbed
            available = true
        } else {
            available = false
        }
    }
}
