import Foundation
import Darwin

/// Enumerates all running processes using proc_listpids / proc_pidinfo.
/// Filters out processes using < 10MB memory.
struct ProcessScanner: Sendable {

    static let minimumMemoryBytes: UInt64 = 10 * 1_048_576 // 10 MB

    func scan() -> [RawProcessInfo] {
        let pids = allPIDs()
        var results: [RawProcessInfo] = []
        results.reserveCapacity(pids.count / 4)

        for pid in pids {
            guard let info = processInfo(for: pid) else { continue }
            if info.memoryBytes >= Self.minimumMemoryBytes {
                results.append(info)
            }
        }
        return results
    }

    // MARK: - Private

    private func allPIDs() -> [pid_t] {
        let bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bufferSize > 0 else { return [] }

        let count = Int(bufferSize) / MemoryLayout<pid_t>.size
        var pids = [pid_t](repeating: 0, count: count)
        let actualSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, bufferSize)
        let actualCount = Int(actualSize) / MemoryLayout<pid_t>.size
        return Array(pids.prefix(actualCount)).filter { $0 > 0 }
    }

    private func processInfo(for pid: pid_t) -> RawProcessInfo? {
        var taskInfo = proc_taskallinfo()
        let size = MemoryLayout<proc_taskallinfo>.size
        let ret = proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &taskInfo, Int32(size))
        guard ret == size else { return nil }

        let name = processName(from: taskInfo)
        let path = processPath(for: pid)
        let cmdLine = commandLine(for: pid)

        let memBytes = taskInfo.ptinfo.pti_resident_size
        let cpuUser = taskInfo.ptinfo.pti_total_user
        let cpuSys = taskInfo.ptinfo.pti_total_system
        let ppid = taskInfo.pbsd.pbi_ppid

        return RawProcessInfo(
            id: pid,
            name: name,
            path: path,
            commandLine: cmdLine,
            memoryBytes: memBytes,
            cpuTimeUser: cpuUser,
            cpuTimeSystem: cpuSys,
            parentPID: pid_t(ppid)
        )
    }

    private func processName(from info: proc_taskallinfo) -> String {
        let comm = info.pbsd.pbi_comm
        return withUnsafePointer(to: comm) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: comm)) { cStr in
                String(cString: cStr)
            }
        }
    }

    private func processPath(for pid: pid_t) -> String {
        var pathBuffer = [CChar](repeating: 0, count: 4096)  // PROC_PIDPATHINFO_MAXSIZE
        let ret = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        guard ret > 0 else { return "" }
        return String(cString: pathBuffer)
    }

    private func commandLine(for pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: size_t = 0

        // Get size
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }

        // First 4 bytes = argc
        guard size > MemoryLayout<Int32>.size else { return [] }
        let argc = buffer.withUnsafeBufferPointer { buf in
            buf.baseAddress!.withMemoryRebound(to: Int32.self, capacity: 1) { $0.pointee }
        }

        // Skip past argc + executable path + null padding
        var offset = MemoryLayout<Int32>.size

        // Skip executable path
        while offset < size && buffer[offset] != 0 { offset += 1 }
        // Skip null padding
        while offset < size && buffer[offset] == 0 { offset += 1 }

        // Parse arguments
        var args: [String] = []
        var argStart = offset
        var count: Int32 = 0

        while offset < size && count < argc {
            if buffer[offset] == 0 {
                let arg = buffer[argStart..<offset].withUnsafeBufferPointer { buf in
                    String(bytes: buf, encoding: .utf8) ?? ""
                }
                args.append(arg)
                count += 1
                argStart = offset + 1
            }
            offset += 1
        }

        return args
    }
}
