import Foundation

/// Enriches classified processes with Ollama API data and health checks.
struct ServiceEnricher: Sendable {
    let ollamaClient: OllamaClient
    let healthChecker: HealthChecker

    /// Enrich processes with Ollama model info and port/health data.
    func enrich(_ processes: inout [ClassifiedProcess], portMap: [pid_t: UInt16]) async {
        // Fetch Ollama running models
        let runningModels = await ollamaClient.runningModels()

        // Assign ports
        for i in processes.indices {
            processes[i].port = portMap[processes[i].id]
        }

        // Match ollama_llama_server processes to running models
        let ollamaProcesses = processes.indices.filter { processes[$0].category == .ollamaRuntime }

        if ollamaProcesses.count == 1 && runningModels.count == 1 {
            // Simple 1:1 match
            let model = runningModels[0]
            let idx = ollamaProcesses[0]
            enrichWithOllamaModel(&processes[idx], model: model)
        } else if !ollamaProcesses.isEmpty && !runningModels.isEmpty {
            // Match by memory size (closest match)
            var usedModels: Set<Int> = []
            for idx in ollamaProcesses {
                let procMem = processes[idx].raw.memoryBytes
                var bestMatch: Int?
                var bestDiff: UInt64 = .max
                for (mi, model) in runningModels.enumerated() {
                    if usedModels.contains(mi) { continue }
                    let diff = procMem > model.size_vram
                        ? procMem - model.size_vram
                        : model.size_vram - procMem
                    if diff < bestDiff {
                        bestDiff = diff
                        bestMatch = mi
                    }
                }
                if let mi = bestMatch {
                    usedModels.insert(mi)
                    enrichWithOllamaModel(&processes[idx], model: runningModels[mi])
                }
            }
        }

        // Health check services with ports
        for i in processes.indices {
            guard let port = processes[i].port,
                  processes[i].category.isService else { continue }
            let result = await healthChecker.check(port: port)
            processes[i].serviceHealthy = result.isHealthy
        }
    }

    private func enrichWithOllamaModel(_ process: inout ClassifiedProcess, model: OllamaRunningModel) {
        process.ollamaModelName = model.name
        process.ollamaQuantization = model.quantization
        process.ollamaSizeVRAM = model.size_vram
        process.ollamaExpiresAt = model.expiresAt
        process.displayName = model.name
    }
}
