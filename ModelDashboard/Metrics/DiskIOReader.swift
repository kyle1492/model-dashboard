import Foundation
import IOKit

/// Reads disk I/O throughput via IOKit IOBlockStorageDriver statistics.
final class DiskIOReader: Sendable {

    nonisolated(unsafe) private var previousRead: UInt64 = 0
    nonisolated(unsafe) private var previousWrite: UInt64 = 0
    nonisolated(unsafe) private var previousTime: ContinuousClock.Instant?
    nonisolated(unsafe) private let lock = NSLock()

    func read() -> DiskIO {
        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0

        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOBlockStorageDriver")
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == KERN_SUCCESS else { return .zero }
        defer { IOObjectRelease(iterator) }

        var entry: io_object_t = IOIteratorNext(iterator)
        while entry != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let stats = dict["Statistics"] as? [String: Any] {
                if let readBytes = stats["Bytes (Read)"] as? UInt64 {
                    totalRead += readBytes
                }
                if let writeBytes = stats["Bytes (Write)"] as? UInt64 {
                    totalWrite += writeBytes
                }
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }

        lock.lock()
        let now = ContinuousClock.now
        var io = DiskIO.zero

        if let prevTime = previousTime {
            let elapsed = now - prevTime
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            if seconds > 0 {
                let deltaRead = totalRead >= previousRead ? totalRead - previousRead : 0
                let deltaWrite = totalWrite >= previousWrite ? totalWrite - previousWrite : 0
                io = DiskIO(
                    readBytesPerSec: UInt64(Double(deltaRead) / seconds),
                    writeBytesPerSec: UInt64(Double(deltaWrite) / seconds)
                )
            }
        }

        previousRead = totalRead
        previousWrite = totalWrite
        previousTime = now
        lock.unlock()

        return io
    }
}
