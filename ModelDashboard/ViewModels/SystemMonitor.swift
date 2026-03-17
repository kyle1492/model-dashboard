import Foundation
import Observation

/// Central state holder and polling scheduler for the dashboard.
@Observable
@MainActor
final class SystemMonitor {

    // MARK: - Published state

    var systemMemory = SystemMemoryInfo.zero
    var memoryBreakdown = MemoryBreakdown()
    var processes: [ClassifiedProcess] = []
    var modelProcesses: [ClassifiedProcess] = []
    var unknownLargeProcesses: [ClassifiedProcess] = []
    var topProcesses: [ClassifiedProcess] = []

    var ollamaAvailable = false
    var runningModels: [OllamaRunningModel] = []
    var installedModels: [OllamaInstalledModel] = []

    var cpuUsage = CPUUsageInfo.zero
    var gpuMetrics = GPUMetrics.zero
    var gpuAvailable = false
    var gpuCoreCount: Int = 0
    var temperature = TemperatureReadings.zero
    var throttle = ThrottleInfo.nominal
    var networkIO = NetworkIO.zero
    var diskIO = DiskIO.zero

    // Sparkline histories (60 data points)
    var cpuHistory = RingBuffer<Double>(capacity: 60, defaultValue: 0)
    var gpuHistory = RingBuffer<Double>(capacity: 60, defaultValue: 0)
    var netInHistory = RingBuffer<Double>(capacity: 60, defaultValue: 0)
    var netOutHistory = RingBuffer<Double>(capacity: 60, defaultValue: 0)
    var diskReadHistory = RingBuffer<Double>(capacity: 60, defaultValue: 0)
    var diskWriteHistory = RingBuffer<Double>(capacity: 60, defaultValue: 0)

    var machineModel: String = ""

    // MARK: - Workers (non-observable)

    private let scanner = ProcessScanner()
    private let classifier = ProcessClassifier()
    private let memoryAnalyzer = MemoryAnalyzer()
    private let ollamaClient = OllamaClient()
    private let healthChecker = HealthChecker()
    private let portMapper = PortMapper()
    private let cpuReader = CPUReader()
    private let ioReportReader = IOReportReader()
    private let throttleReader = ThrottleReader()
    private let tempReader = TemperatureReader()
    private let networkReader = NetworkIOReader()
    private let diskReader = DiskIOReader()

    private var enricher: ServiceEnricher {
        ServiceEnricher(ollamaClient: ollamaClient, healthChecker: healthChecker)
    }

    private var fastTimer: Timer?   // 1s — CPU, GPU, Network
    private var slowTimer: Timer?   // 2s — processes, memory, disk, temperature
    private var ollamaTimer: Timer? // 5s — Ollama API, port mapping

    // MARK: - Lifecycle

    func start() {
        machineModel = Self.getMachineModel()
        gpuAvailable = ioReportReader.isAvailable
        gpuCoreCount = Self.getGPUCoreCount()

        // Initial read
        Task { await refreshAll() }

        // Fast timer: 1s
        fastTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshFast()
            }
        }

        // Slow timer: 2s
        slowTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshSlow()
            }
        }

        // Ollama timer: 5s
        ollamaTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshOllama()
            }
        }
    }

    func stop() {
        fastTimer?.invalidate()
        slowTimer?.invalidate()
        ollamaTimer?.invalidate()
    }

    // MARK: - Refresh cycles

    private func refreshAll() async {
        refreshFast()
        await refreshSlow()
        await refreshOllama()
    }

    /// ~1s cycle: CPU, GPU, network
    nonisolated private func readCPU(reader: CPUReader) -> CPUUsageInfo {
        reader.read()
    }
    nonisolated private func readGPU(reader: IOReportReader) -> GPUMetrics {
        reader.read()
    }
    nonisolated private func readNetwork(reader: NetworkIOReader) -> NetworkIO {
        reader.read()
    }

    private func refreshFast() {
        let cpu = readCPU(reader: cpuReader)
        cpuUsage = cpu
        cpuHistory.append(cpu.overallAverage)

        if gpuAvailable {
            let gpu = readGPU(reader: ioReportReader)
            if gpu.isAvailable {
                gpuMetrics = gpu
                gpuHistory.append(gpu.utilizationPercent / 100)
            }
        }

        let net = readNetwork(reader: networkReader)
        networkIO = net
        netInHistory.append(net.inMBps)
        netOutHistory.append(net.outMBps)
    }

    /// ~2s cycle: processes, memory, disk, temperature
    private func refreshSlow() async {
        // Process scan + classify (off main thread)
        let scanned = await Task.detached { [scanner, classifier] in
            let raw = scanner.scan()
            return classifier.classify(raw)
        }.value

        systemMemory = memoryAnalyzer.systemMemory()
        memoryBreakdown = memoryAnalyzer.breakdown(systemMem: systemMemory, processes: scanned)

        // Filter and sort
        processes = scanned.filter { $0.category != .system && $0.category != .other }
        var models = scanned.filter { $0.category.isModel }
            .sorted { $0.raw.memoryBytes > $1.raw.memoryBytes }

        // Inline enrichment using cached Ollama data
        applyOllamaEnrichment(&models)

        modelProcesses = models
        unknownLargeProcesses = scanned.filter { $0.category == .unknownLarge }
        topProcesses = scanned
            .filter { $0.category != .system }
            .sorted { $0.raw.memoryBytes > $1.raw.memoryBytes }
            .prefix(10)
            .map { $0 }

        // Disk I/O
        let disk = await Task.detached { [diskReader] in diskReader.read() }.value
        diskIO = disk
        diskReadHistory.append(disk.readMBps)
        diskWriteHistory.append(disk.writeMBps)

        // Temperature (must run on main thread — HID API is thread-sensitive)
        temperature = tempReader.read()

        // Throttle state
        throttle = throttleReader.read()
    }

    /// ~5s cycle: Ollama API + port mapping + enrichment
    private func refreshOllama() async {
        ollamaAvailable = await ollamaClient.isAvailable()

        if ollamaAvailable {
            runningModels = await ollamaClient.runningModels()
            installedModels = await ollamaClient.installedModels()
        }

        await portMapper.refresh()
        let portMap = await portMapper.allMappings()

        // Enrich model processes
        var enriched = modelProcesses
        await enricher.enrich(&enriched, portMap: portMap)
        modelProcesses = enriched

        // Also update port info in top processes
        for i in topProcesses.indices {
            topProcesses[i].port = portMap[topProcesses[i].id]
        }
    }

    // MARK: - Inline Ollama enrichment (uses cached runningModels)

    private func applyOllamaEnrichment(_ processes: inout [ClassifiedProcess]) {
        guard !runningModels.isEmpty else { return }

        let ollamaProcesses = processes.indices.filter { processes[$0].category == .ollamaRuntime }
        guard !ollamaProcesses.isEmpty else { return }

        if ollamaProcesses.count == 1 && runningModels.count == 1 {
            let model = runningModels[0]
            let idx = ollamaProcesses[0]
            processes[idx].ollamaModelName = model.name
            processes[idx].ollamaQuantization = model.quantization
            processes[idx].ollamaSizeVRAM = model.size_vram
            processes[idx].ollamaExpiresAt = model.expiresAt
            processes[idx].displayName = model.name
        } else {
            // Match by memory size
            var usedModels: Set<Int> = []
            for idx in ollamaProcesses {
                let procMem = processes[idx].raw.memoryBytes
                var bestMatch: Int?
                var bestDiff: UInt64 = .max
                for (mi, model) in runningModels.enumerated() {
                    if usedModels.contains(mi) { continue }
                    let diff = procMem > model.size_vram ? procMem - model.size_vram : model.size_vram - procMem
                    if diff < bestDiff {
                        bestDiff = diff
                        bestMatch = mi
                    }
                }
                if let mi = bestMatch {
                    usedModels.insert(mi)
                    let model = runningModels[mi]
                    processes[idx].ollamaModelName = model.name
                    processes[idx].ollamaQuantization = model.quantization
                    processes[idx].ollamaSizeVRAM = model.size_vram
                    processes[idx].ollamaExpiresAt = model.expiresAt
                    processes[idx].displayName = model.name
                }
            }
        }
    }

    // MARK: - Hardware info

    private static func getGPUCoreCount() -> Int {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        process.arguments = ["-l"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if let output = String(data: data, encoding: .utf8),
               let range = output.range(of: "\"gpu-core-count\" = "),
               let numStart = output[range.upperBound...].first(where: { $0.isNumber }) {
                let numStr = String(output[range.upperBound...].prefix(while: { $0.isNumber || $0 == " " })).trimmingCharacters(in: .whitespaces)
                if let count = Int(numStr) { return count }
            }
        } catch {}
        return 0 // unknown — View layer will hide GPU grid
    }

    private static func getMachineModel() -> String {
        var size: size_t = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let raw = String(cString: model)

        // Also get the marketing name
        var chipSize: size_t = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &chipSize, nil, 0)
        if chipSize > 0 {
            var chip = [CChar](repeating: 0, count: chipSize)
            sysctlbyname("machdep.cpu.brand_string", &chip, &chipSize, nil, 0)
            let chipName = String(cString: chip)
            if !chipName.isEmpty { return chipName }
        }

        return raw
    }
}
