import SwiftUI

/// GPU metrics panel with core grid, utilization, and sparkline.
struct GPUPanelView: View {
    let metrics: GPUMetrics
    let history: [Double]
    let available: Bool
    let coreCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with utilization and power
            HStack(spacing: 8) {
                Text("GPU")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                if available && metrics.isAvailable {
                    Spacer()
                    HStack(spacing: 4) {
                        Text("\(Int(metrics.utilizationPercent))%")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(gpuColor)
                        if metrics.powerWatts > 0 {
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.0fW", metrics.powerWatts))
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            if !available {
                Text("GPU metrics require Apple Silicon Mac")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                // GPU core grid — all cores share overall utilization
                if coreCount > 0 {
                    GPUCoreGrid(
                        coreCount: coreCount,
                        utilization: metrics.utilizationPercent / 100,
                        pStateDistribution: metrics.pStateDistribution
                    )
                }

                // Sparkline
                SparklineView(values: history, color: .cyan)
                    .frame(height: 24)
            }
        }
    }

    private var gpuColor: Color {
        let v = metrics.utilizationPercent
        if v < 50 { return .green }
        if v < 80 { return .yellow }
        return .red
    }
}

/// GPU core grid — shows cores colored by overall utilization.
/// Since Apple Silicon GPU doesn't expose per-core utilization,
/// all cores share the same overall utilization level, with slight
/// random variation for visual interest based on P-state distribution.
private struct GPUCoreGrid: View {
    let coreCount: Int
    let utilization: Double  // 0.0 - 1.0
    let pStateDistribution: [GPUMetrics.PStateSlice]

    // 10 columns to match 40 cores = 10×4 grid
    private var columnCount: Int {
        if coreCount <= 16 { return 8 }
        if coreCount <= 32 { return 8 }
        return 10
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(14), spacing: 2), count: columnCount)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(0..<coreCount, id: \.self) { i in
                CoreCell(usage: coreUsage(for: i), size: 14)
            }
        }
    }

    /// Distribute slight variation across cores based on P-state data.
    /// Cores are grouped into clusters (10 per cluster for 40-core GPU),
    /// with each cluster getting a slight offset to show activity pattern.
    private func coreUsage(for index: Int) -> Double {
        guard utilization > 0 else { return 0 }

        let clusterCount = max(1, coreCount / 10)
        let cluster = index / max(1, coreCount / clusterCount)

        // Use golden ratio hash for deterministic but varied distribution
        let hash = Double((index * 2654435761) & 0xFF) / 255.0
        let variation = (hash - 0.5) * 0.15  // ±7.5% variation

        // Clusters closer to 0 are slightly more active (front clusters)
        let clusterBias = Double(clusterCount - 1 - cluster) / Double(max(1, clusterCount - 1)) * 0.05

        return min(1, max(0, utilization + variation + clusterBias))
    }
}
