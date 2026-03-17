import SwiftUI

/// Grid of CPU cores showing per-core utilization.
struct CPUGridView: View {
    let cpuUsage: CPUUsageInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Averages
            HStack(spacing: 16) {
                avgLabel("P-cores", value: cpuUsage.pCoreAverage)
                avgLabel("E-cores", value: cpuUsage.eCoreAverage)
                Spacer()
                Text("\(Int(cpuUsage.overallAverage * 100))%")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(usageColor(cpuUsage.overallAverage))
            }

            // Core grid — P-cores and E-cores side by side
            if !cpuUsage.cores.isEmpty {
                let pCores = cpuUsage.cores.filter(\.isPerformance)
                let eCores = cpuUsage.cores.filter { !$0.isPerformance }

                HStack(alignment: .top, spacing: 6) {
                    // P-cores: 6 columns × 2 rows for 12 cores
                    let pCols = Array(repeating: GridItem(.fixed(18), spacing: 2), count: 6)
                    LazyVGrid(columns: pCols, spacing: 2) {
                        ForEach(pCores) { core in
                            CoreCell(usage: core.usage, size: 18)
                        }
                    }

                    // Divider line
                    Rectangle()
                        .fill(.white.opacity(0.1))
                        .frame(width: 1)
                        .padding(.vertical, 2)

                    // E-cores: 4 columns × 1 row for 4 cores
                    let eCols = Array(repeating: GridItem(.fixed(18), spacing: 2), count: 4)
                    LazyVGrid(columns: eCols, spacing: 2) {
                        ForEach(eCores) { core in
                            CoreCell(usage: core.usage, size: 18)
                        }
                    }
                }
            }
        }
    }

    private func avgLabel(_ label: String, value: Double) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("\(Int(value * 100))%")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(usageColor(value))
        }
    }

    private func usageColor(_ v: Double) -> Color {
        if v < 0.5 { return .green }
        if v < 0.8 { return .yellow }
        return .red
    }
}

/// Single core cell — fill bar from bottom with color gradient.
struct CoreCell: View {
    let usage: Double
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white.opacity(0.05))
            .frame(width: size, height: size)
            .overlay {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor.opacity(0.7))
                        .frame(height: size * CGFloat(min(1, max(0, usage))))
                }
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }
    }

    private var barColor: Color {
        if usage < 0.5 { return .green }
        if usage < 0.8 { return .yellow }
        return .red
    }
}
