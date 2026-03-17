import Foundation

/// Maps PIDs to listening TCP ports via lsof.
actor PortMapper {
    private var pidToPort: [pid_t: UInt16] = [:]
    private var portToPid: [UInt16: pid_t] = [:]

    func refresh() async {
        let mapping = await Self.runLsof()
        pidToPort = mapping.pidToPort
        portToPid = mapping.portToPid
    }

    func port(for pid: pid_t) -> UInt16? {
        pidToPort[pid]
    }

    func pid(for port: UInt16) -> pid_t? {
        portToPid[port]
    }

    func allMappings() -> [pid_t: UInt16] {
        pidToPort
    }

    private static func runLsof() async -> (pidToPort: [pid_t: UInt16], portToPid: [UInt16: pid_t]) {
        let lsofPath = "/usr/sbin/lsof"
        guard FileManager.default.isExecutableFile(atPath: lsofPath) else { return ([:], [:]) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: lsofPath)
        process.arguments = ["-iTCP", "-sTCP:LISTEN", "-P", "-n"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return ([:], [:])
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return ([:], [:]) }

        var p2p: [pid_t: UInt16] = [:]
        var port2p: [UInt16: pid_t] = [:]

        for line in output.split(separator: "\n").dropFirst() { // skip header
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            guard cols.count >= 9 else { continue }

            guard let pid = pid_t(cols[1]) else { continue }
            let nameCol = String(cols[8])

            // Parse "host:port" or "*:port"
            if let lastColon = nameCol.lastIndex(of: ":") {
                let portStr = nameCol[nameCol.index(after: lastColon)...]
                if let port = UInt16(portStr) {
                    p2p[pid] = port
                    port2p[port] = pid
                }
            }
        }

        return (p2p, port2p)
    }
}
