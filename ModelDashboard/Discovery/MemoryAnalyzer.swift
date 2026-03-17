import Foundation
import Darwin

/// Reads system-wide memory stats via host_statistics64 and breaks down by process category.
struct MemoryAnalyzer: Sendable {

    func systemMemory() -> SystemMemoryInfo {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else { return .zero }

        let pageSize = UInt64(getpagesize())
        let total = totalPhysicalMemory()

        let wired = UInt64(stats.wire_count) * pageSize
        let active = UInt64(stats.active_count) * pageSize
        let inactive = UInt64(stats.inactive_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let free = UInt64(stats.free_count) * pageSize

        return SystemMemoryInfo(
            totalBytes: total,
            wiredBytes: wired,
            activeBytes: active,
            inactiveBytes: inactive,
            compressedBytes: compressed,
            freeBytes: free
        )
    }

    func breakdown(systemMem: SystemMemoryInfo, processes: [ClassifiedProcess]) -> MemoryBreakdown {
        var modelMem: UInt64 = 0
        var appMem: UInt64 = 0
        var sysMem: UInt64 = 0

        for p in processes {
            switch p.category {
            case .ollamaRuntime, .mlxLM, .embedding, .tts, .stt, .imageGeneration:
                modelMem += p.raw.memoryBytes
            case .userApp, .mlAPI:
                appMem += p.raw.memoryBytes
            case .system, .ollamaPlatform:
                sysMem += p.raw.memoryBytes
            case .unknownLarge, .other:
                appMem += p.raw.memoryBytes
            }
        }

        return MemoryBreakdown(
            modelMemory: modelMem,
            appMemory: appMem,
            systemMemory: systemMem.wiredBytes,
            cacheMemory: systemMem.inactiveBytes,
            freeMemory: systemMem.freeBytes
        )
    }

    private func totalPhysicalMemory() -> UInt64 {
        var size: UInt64 = 0
        var len = MemoryLayout<UInt64>.size
        var mib: [Int32] = [CTL_HW, HW_MEMSIZE]
        sysctl(&mib, 2, &size, &len, nil, 0)
        return size
    }
}
