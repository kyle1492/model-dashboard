import SwiftUI

/// Main dashboard layout — full-screen dark monitoring panel.
struct DashboardView: View {
    @State private var monitor = SystemMonitor()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerBar
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

            Divider().opacity(0.3)

            // Memory bar
            MemoryBarView(
                breakdown: monitor.memoryBreakdown,
                totalGB: monitor.systemMemory.totalGB
            )
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Main content: left panel + right panel
            HStack(alignment: .top, spacing: 16) {
                // Left: models + installed + top processes
                leftPanel
                    .frame(maxWidth: .infinity)

                // Right: system metrics
                rightPanel
                    .frame(width: 280)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .preferredColorScheme(.dark)
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Text("MODEL DASHBOARD")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
            Spacer()
            Text(monitor.machineModel)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Running models
                sectionHeader("RUNNING MODELS", count: monitor.modelProcesses.count)

                if monitor.modelProcesses.isEmpty {
                    Text("No models running")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(monitor.modelProcesses) { process in
                        ModelCardView(process: process)
                    }
                }

                // Unknown large processes warning
                if !monitor.unknownLargeProcesses.isEmpty {
                    sectionHeader("UNKNOWN LARGE PROCESSES", count: monitor.unknownLargeProcesses.count)
                    ForEach(monitor.unknownLargeProcesses) { process in
                        ModelCardView(process: process)
                    }
                }

                Divider().opacity(0.2)

                // Installed models
                ServiceListView(
                    installedModels: monitor.installedModels,
                    runningModelNames: Set(monitor.runningModels.map(\.name)),
                    ollamaAvailable: monitor.ollamaAvailable
                )

                Divider().opacity(0.2)

                // Top processes
                ProcessTableView(processes: monitor.topProcesses)
            }
        }
    }

    // MARK: - Right Panel

    private var rightPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // CPU
                VStack(alignment: .leading, spacing: 8) {
                    Text("CPU")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)

                    CPUGridView(cpuUsage: monitor.cpuUsage)

                    SparklineView(
                        values: monitor.cpuHistory.values,
                        color: .green
                    )
                    .frame(height: 28)
                }

                Divider().opacity(0.2)

                // GPU
                GPUPanelView(
                    metrics: monitor.gpuMetrics,
                    history: monitor.gpuHistory.values,
                    available: monitor.gpuAvailable,
                    coreCount: monitor.gpuCoreCount
                )

                Divider().opacity(0.2)

                // Temperature + Throttle
                temperaturePanel
                throttlePanel

                Divider().opacity(0.2)

                // Network + Disk I/O
                IOPanelView(
                    networkIO: monitor.networkIO,
                    diskIO: monitor.diskIO,
                    netInHistory: monitor.netInHistory.values,
                    netOutHistory: monitor.netOutHistory.values,
                    diskReadHistory: monitor.diskReadHistory.values,
                    diskWriteHistory: monitor.diskWriteHistory.values
                )
            }
        }
    }

    // MARK: - Temperature

    private var temperaturePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TEMP")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            let t = monitor.temperature

            // CPU + GPU: avg / P90 / max
            if t.cpuTemp != nil || t.gpuTemp != nil {
                Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 3) {
                    // Header row
                    GridRow {
                        Text("")
                            .gridColumnAlignment(.leading)
                        Text("avg")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                        Text("P90")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                        Text("max")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }

                    if let cpu = t.cpuTemp {
                        tempStatsRow("CPU", stats: cpu)
                    }
                    if let gpu = t.gpuTemp {
                        tempStatsRow("GPU", stats: gpu)
                    }
                }
            }

            // SSD + Ambient (single values)
            HStack(spacing: 16) {
                if let ssd = t.ssdTemp {
                    singleTempLabel("SSD", value: ssd)
                }
                if let amb = t.ambientTemp {
                    singleTempLabel("Ambient", value: amb)
                }
            }
        }
    }

    @ViewBuilder
    private func tempStatsRow(_ name: String, stats: TempStats) -> some View {
        GridRow {
            Text(name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            tempValue(stats.avg)
            tempValue(stats.p90)
            tempValue(stats.max)
        }
    }

    private func tempValue(_ temp: Double) -> some View {
        Text("\(Int(temp))°")
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .foregroundStyle(tempColor(temp))
    }

    private func singleTempLabel(_ name: String, value: Double) -> some View {
        VStack(spacing: 2) {
            Text(name)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("\(Int(value))°C")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(tempColor(value))
        }
    }

    private func tempColor(_ temp: Double) -> Color {
        if temp < 50 { return .green }
        if temp < 75 { return .yellow }
        return .red
    }

    // MARK: - Throttle

    private var throttlePanel: some View {
        let t = monitor.throttle
        return VStack(alignment: .leading, spacing: 4) {
            if t.isThrottled {
                // Thermal state badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(throttleStateColor(t.thermalState))
                        .frame(width: 8, height: 8)
                    Text("Thermal: \(t.thermalStateLabel)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(throttleStateColor(t.thermalState))
                }

                // GPU frequency ratio
                if t.gpuFreqRatio < 0.95 {
                    HStack(spacing: 4) {
                        Text("GPU freq")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("\(Int(t.gpuFreqRatio * 100))%")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.orange)
                        if t.gpuCLTMActive {
                            Text("CLTM")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(.red.opacity(0.8))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.red.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                }

                // CPU cluster throttle
                if t.cpuClusterRatio < 0.95 {
                    HStack(spacing: 4) {
                        Text("CPU P-cluster2")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("\(Int(t.cpuClusterRatio * 100))% active")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private func throttleStateColor(_ state: Int) -> Color {
        switch state {
        case 0: .green
        case 1: .yellow
        case 2: .orange
        case 3: .red
        default: .gray
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
            if count > 0 {
                Text("(\(count))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
