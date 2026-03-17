import Foundation
import Darwin

/// Reads network throughput using getifaddrs() with delta calculation.
final class NetworkIOReader: Sendable {

    nonisolated(unsafe) private var previousIn: UInt64 = 0
    nonisolated(unsafe) private var previousOut: UInt64 = 0
    nonisolated(unsafe) private var previousTime: ContinuousClock.Instant?
    nonisolated(unsafe) private let lock = NSLock()

    func read() -> NetworkIO {
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return .zero
        }
        defer { freeifaddrs(ifaddr) }

        var ptr = firstAddr
        while true {
            let name = String(cString: ptr.pointee.ifa_name)
            // Skip loopback
            if name != "lo0" && ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK) {
                if let data = ptr.pointee.ifa_data {
                    let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                    totalIn += UInt64(networkData.ifi_ibytes)
                    totalOut += UInt64(networkData.ifi_obytes)
                }
            }
            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }

        lock.lock()
        let now = ContinuousClock.now
        var result = NetworkIO.zero

        if let prevTime = previousTime {
            let elapsed = now - prevTime
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            if seconds > 0 {
                let deltaIn = totalIn >= previousIn ? totalIn - previousIn : 0
                let deltaOut = totalOut >= previousOut ? totalOut - previousOut : 0
                result = NetworkIO(
                    bytesInPerSec: UInt64(Double(deltaIn) / seconds),
                    bytesOutPerSec: UInt64(Double(deltaOut) / seconds)
                )
            }
        }

        previousIn = totalIn
        previousOut = totalOut
        previousTime = now
        lock.unlock()

        return result
    }
}
