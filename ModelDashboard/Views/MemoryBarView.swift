import SwiftUI

/// Full-width memory breakdown bar with labels.
struct MemoryBarView: View {
    let breakdown: MemoryBreakdown
    let totalGB: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title
            HStack {
                Text("MEMORY")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("(\(formatGB(totalGB)))")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            // Segmented bar
            SegmentedBarView(
                segments: [
                    .init(label: "Models", value: breakdown.modelGB, color: .green),
                    .init(label: "Apps", value: breakdown.appGB, color: .blue),
                    .init(label: "System", value: breakdown.systemGB, color: .orange),
                    .init(label: "Cache", value: breakdown.cacheGB, color: .gray.opacity(0.5), isStriped: true),
                    .init(label: "Free", value: breakdown.freeGB, color: .black.opacity(0.3)),
                ],
                totalValue: totalGB,
                height: 24
            )

            // Legend
            HStack(spacing: 16) {
                legendItem("Models", value: breakdown.modelGB, color: .green)
                legendItem("Apps", value: breakdown.appGB, color: .blue)
                legendItem("System", value: breakdown.systemGB, color: .orange)
                legendItem("Cache", value: breakdown.cacheGB, color: .gray.opacity(0.5), note: "reclaimable")
                legendItem("Free", value: breakdown.freeGB, color: .white.opacity(0.2))
            }
            .font(.system(size: 10, design: .monospaced))
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.03)))
    }

    private func legendItem(_ label: String, value: Double, color: Color, note: String? = nil) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(label) \(formatGB(value))")
                .foregroundStyle(.secondary)
            if let note {
                Text(note)
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 9))
            }
        }
    }

    private func formatGB(_ gb: Double) -> String {
        String(format: "%.1fGB", gb)
    }
}
