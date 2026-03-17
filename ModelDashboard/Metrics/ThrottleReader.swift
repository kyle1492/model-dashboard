import Foundation

/// Reads throttle state from IOReport (GPU P-states, CLTM) and ProcessInfo (thermal state).
final class ThrottleReader: @unchecked Sendable {

    private var subscription: IOReportSubscriptionRef?
    private var subscribedChannels: CFMutableDictionary?
    private var previousSample: CFDictionary?
    private let lock = NSLock()
    private(set) var isAvailable = false

    init() {
        setup()
    }

    func read() -> ThrottleInfo {
        var info = ThrottleInfo()

        // Thermal state from ProcessInfo
        let state = ProcessInfo.processInfo.thermalState
        switch state {
        case .nominal:  info.thermalState = 0
        case .fair:     info.thermalState = 1
        case .serious:  info.thermalState = 2
        case .critical: info.thermalState = 3
        @unknown default: info.thermalState = 0
        }

        guard isAvailable else { return info }

        lock.lock()
        defer { lock.unlock() }

        guard let sub = subscription, let channels = subscribedChannels else { return info }
        guard let currentU = IOReportCreateSamples(sub, channels, nil) else { return info }
        let current = currentU.takeRetainedValue()

        defer { previousSample = current }
        guard let prev = previousSample else { previousSample = current; return info }

        guard let deltaU = IOReportCreateSamplesDelta(prev, current, nil) else { return info }
        let delta = deltaU.takeRetainedValue()

        guard let chArray = (delta as NSDictionary)["IOReportChannels"] as? [NSDictionary] else { return info }

        // Collect raw data first, compute ratios after
        var gpuPHStates: [(pState: Int, residency: Int64)] = []
        var gpuPHTotal: Int64 = 0
        var boostTarget: Int = 0
        var cltmNoCLTMFraction: Double = 0
        var cluster1DownFractions: [Double] = []

        for ch in chArray {
            let cf = ch as CFDictionary
            let group = (IOReportChannelGetGroup(cf)?.takeUnretainedValue()) as String? ?? ""
            let subgroup = (IOReportChannelGetSubGroup(cf)?.takeUnretainedValue()) as String? ?? ""
            let name = (IOReportChannelGetChannelName(cf)?.takeUnretainedValue()) as String? ?? ""

            if group == "GPU Stats" && subgroup == "GPU Performance States" && name == "GPUPH" {
                let sc = IOReportStateGetCount(cf)
                for s in 0..<sc {
                    let res = IOReportStateGetResidency(cf, s)
                    let sName = (IOReportStateGetNameForIndex(cf, s)?.takeUnretainedValue()) as String? ?? ""
                    gpuPHTotal += res
                    if sName != "OFF", let p = pStateNum(sName), res > 0 {
                        gpuPHStates.append((p, res))
                    }
                }
            }

            if group == "GPU Stats" && name == "BSTGPUPH" {
                let sc = IOReportStateGetCount(cf)
                for s in (0..<sc).reversed() {
                    let res = IOReportStateGetResidency(cf, s)
                    if res > 0 {
                        let sName = (IOReportStateGetNameForIndex(cf, s)?.takeUnretainedValue()) as String? ?? ""
                        if let p = pStateNum(sName) { boostTarget = p }
                        break
                    }
                }
            }

            if group == "GPU Stats" && name == "GPU_CLTM" {
                let sc = IOReportStateGetCount(cf)
                var total: Int64 = 0
                var noCLTM: Int64 = 0
                for s in 0..<sc {
                    let res = IOReportStateGetResidency(cf, s)
                    let sName = (IOReportStateGetNameForIndex(cf, s)?.takeUnretainedValue()) as String? ?? ""
                    total += res
                    if sName == "NO_CLTM" { noCLTM = res }
                }
                if total > 0 { cltmNoCLTMFraction = Double(noCLTM) / Double(total) }
            }

            if group == "CPU Stats" && subgroup == "CPU Core Performance States" && name.hasPrefix("PCPU1") {
                let sc = IOReportStateGetCount(cf)
                var total: Int64 = 0
                var down: Int64 = 0
                for s in 0..<sc {
                    let res = IOReportStateGetResidency(cf, s)
                    let sName = (IOReportStateGetNameForIndex(cf, s)?.takeUnretainedValue()) as String? ?? ""
                    total += res
                    if sName == "DOWN" { down = res }
                }
                if total > 0 { cluster1DownFractions.append(Double(down) / Double(total)) }
            }
        }

        // Compute GPU freq ratio: weighted avg P-state / boost target
        if boostTarget > 0 && !gpuPHStates.isEmpty {
            let activeRes = gpuPHStates.reduce(Int64(0)) { $0 + $1.residency }
            if activeRes > 0 {
                let weightedAvg = gpuPHStates.reduce(0.0) { $0 + Double($1.pState) * Double($1.residency) / Double(activeRes) }
                info.gpuFreqRatio = min(1.0, weightedAvg / Double(boostTarget))
                info.gpuActivePState = gpuPHStates.max(by: { $0.pState < $1.pState })?.pState ?? 0
                info.gpuMaxPState = boostTarget
            }
        }

        // CLTM active if NO_CLTM < 50%
        info.gpuCLTMActive = cltmNoCLTMFraction < 0.5

        // CPU cluster2: only flag as throttle if thermal state is elevated
        // When thermal state is nominal, cluster2 being down is normal power management
        if info.thermalState > 0 && !cluster1DownFractions.isEmpty {
            let avgDown = cluster1DownFractions.reduce(0, +) / Double(cluster1DownFractions.count)
            info.cpuClusterRatio = 1.0 - avgDown
        }

        return info
    }

    private func pStateNum(_ name: String) -> Int? {
        guard name.hasPrefix("P"), let n = Int(name.dropFirst()) else { return nil }
        return n
    }

    // MARK: - Setup

    private func setup() {
        guard let cpuU = IOReportCopyChannelsInGroup("CPU Stats" as CFString, nil, 0, 0, 0) else { return }
        let merged = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, cpuU.takeRetainedValue())!

        if let gpuU = IOReportCopyChannelsInGroup("GPU Stats" as CFString, nil, 0, 0, 0) {
            let gpuM = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, gpuU.takeRetainedValue())!
            IOReportMergeChannels(merged, gpuM, nil)
        }

        var subbedU: Unmanaged<CFMutableDictionary>?
        let sub = IOReportCreateSubscription(nil, merged, &subbedU, 0, nil)

        if sub != nil, let subbed = subbedU?.takeRetainedValue() {
            subscription = sub
            subscribedChannels = subbed
            isAvailable = true
        }
    }
}
