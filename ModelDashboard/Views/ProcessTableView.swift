import SwiftUI

/// Top processes table sorted by memory.
struct ProcessTableView: View {
    let processes: [ClassifiedProcess]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TOP PROCESSES")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            // Header
            HStack {
                Text("PID")
                    .frame(width: 50, alignment: .leading)
                Text("Name")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Memory")
                    .frame(width: 70, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.tertiary)

            ForEach(processes) { process in
                HStack {
                    Text("\(process.id)")
                        .frame(width: 50, alignment: .leading)

                    HStack(spacing: 4) {
                        Text(process.displayName)
                            .lineLimit(1)
                        if process.category == .unknownLarge {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.yellow)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(formatMemory(process.raw.memoryBytes))
                        .frame(width: 70, alignment: .trailing)
                        .foregroundStyle(process.raw.memoryGB >= 1 ? .green : .secondary)
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    private func formatMemory(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        return String(format: "%.0f MB", Double(bytes) / 1_048_576)
    }
}
