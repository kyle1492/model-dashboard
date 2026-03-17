import SwiftUI

/// Network and Disk I/O panel with sparklines.
struct IOPanelView: View {
    let networkIO: NetworkIO
    let diskIO: DiskIO
    let netInHistory: [Double]
    let netOutHistory: [Double]
    let diskReadHistory: [Double]
    let diskWriteHistory: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Network
            VStack(alignment: .leading, spacing: 4) {
                Text("NET")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                HStack {
                    Label {
                        Text(formatRate(networkIO.inMBps))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                    } icon: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                    }

                    Label {
                        Text(formatRate(networkIO.outMBps))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                    } icon: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 10))
                            .foregroundStyle(.blue)
                    }
                }
                .foregroundStyle(.white)

                ZStack {
                    SparklineView(values: netInHistory, color: .green)
                    SparklineView(values: netOutHistory, color: .blue.opacity(0.7))
                }
                .frame(height: 28)
            }

            // Disk
            VStack(alignment: .leading, spacing: 4) {
                Text("DISK")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                HStack {
                    Label {
                        Text(formatRate(diskIO.readMBps))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                    } icon: {
                        Text("R")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.green)
                    }

                    Label {
                        Text(formatRate(diskIO.writeMBps))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                    } icon: {
                        Text("W")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.orange)
                    }
                }
                .foregroundStyle(.white)

                ZStack {
                    SparklineView(values: diskReadHistory, color: .green)
                    SparklineView(values: diskWriteHistory, color: .orange.opacity(0.7))
                }
                .frame(height: 28)
            }
        }
    }

    private func formatRate(_ mbps: Double) -> String {
        if mbps >= 1 {
            return String(format: "%.1f MB/s", mbps)
        }
        let kbps = mbps * 1024
        if kbps >= 1 {
            return String(format: "%.0f KB/s", kbps)
        }
        return "0 B/s"
    }
}
