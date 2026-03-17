import Foundation

/// Rule-based classifier: matches processes by priority, first-match wins.
struct ProcessClassifier: Sendable {

    private static let systemProcessNames: Set<String> = [
        "kernel_task", "launchd", "WindowServer", "loginwindow",
        "coreaudiod", "corebrightnessd", "sharingd", "bluetoothd",
        "airportd", "fseventsd", "mds_stores", "mds", "mdworker_shared",
        "distnoted", "cfprefsd", "syslogd", "notifyd"
    ]

    private static let systemPathPrefixes: [String] = [
        "/usr/libexec/", "/System/", "/usr/sbin/", "/usr/bin/",
        "/Library/Apple/"
    ]

    func classify(_ processes: [RawProcessInfo]) -> [ClassifiedProcess] {
        processes.map(classifySingle)
    }

    func classifySingle(_ p: RawProcessInfo) -> ClassifiedProcess {
        let cat = determineCategory(p)
        let name = displayName(for: p, category: cat)
        return ClassifiedProcess(
            id: p.id,
            raw: p,
            category: cat,
            displayName: name
        )
    }

    // MARK: - Priority-based classification

    private func determineCategory(_ p: RawProcessInfo) -> ProcessCategory {
        // 1. System processes
        if p.id <= 1 { return .system }
        if Self.systemProcessNames.contains(p.name) { return .system }
        if Self.systemPathPrefixes.contains(where: { p.path.hasPrefix($0) }) { return .system }

        // 2 & 3. Ollama — distinguish runner vs serve by command line
        if p.name == "ollama" || p.name == "ollama_llama_server" {
            let cmdJoined = p.commandLine.joined(separator: " ")
            // "ollama runner" or "ollama_llama_server" = model runtime (holds model memory)
            if cmdJoined.contains("runner") || p.name == "ollama_llama_server" {
                return .ollamaRuntime
            }
            // "ollama serve" = platform process
            return .ollamaPlatform
        }

        // 4. Python ML processes — parse command line
        if p.name.hasPrefix("python") || p.name.hasPrefix("Python") {
            return classifyPython(p)
        }

        // 5. User apps
        if p.path.contains("/Applications/") && p.path.contains(".app/") {
            return .userApp
        }

        // 6. Unknown large process (>1GB)
        if p.memoryBytes > 1_073_741_824 { return .unknownLarge }

        // 7. Other
        return .other
    }

    private func classifyPython(_ p: RawProcessInfo) -> ProcessCategory {
        let cmdJoined = p.commandLine.joined(separator: " ").lowercased()

        // Order matters: more specific first
        if cmdJoined.contains("mlx_lm") || cmdJoined.contains("mlx-lm") {
            return .mlxLM
        }
        if cmdJoined.contains("embed") || cmdJoined.contains("bge") ||
           cmdJoined.contains("sentence_transformers") || cmdJoined.contains("sentence-transformers") {
            return .embedding
        }
        if cmdJoined.contains("tts") || cmdJoined.contains("speech") || cmdJoined.contains("edge-tts") {
            return .tts
        }
        if cmdJoined.contains("whisper") {
            return .stt
        }
        if cmdJoined.contains("diffuser") || cmdJoined.contains("stable_diffusion") ||
           cmdJoined.contains("flux") || cmdJoined.contains("qwen-image") {
            return .imageGeneration
        }
        if cmdJoined.contains("uvicorn") || cmdJoined.contains("fastapi") ||
           cmdJoined.contains("flask") || cmdJoined.contains("gunicorn") {
            return .mlAPI
        }

        // Large unclassified Python
        if p.memoryBytes > 1_073_741_824 { return .unknownLarge }

        return .other
    }

    private func displayName(for p: RawProcessInfo, category: ProcessCategory) -> String {
        switch category {
        case .ollamaRuntime:
            return "Ollama Model" // will be enriched by ServiceEnricher
        case .ollamaPlatform:
            return "Ollama"
        case .mlxLM:
            return extractMLXModelName(p) ?? "MLX LM"
        case .embedding:
            return extractServiceName(p, fallback: "Embedding Service")
        case .tts:
            return "TTS Service"
        case .stt:
            return "Whisper STT"
        case .imageGeneration:
            return "Image Generation"
        case .mlAPI:
            return extractServiceName(p, fallback: "ML API")
        case .userApp:
            return extractAppName(p)
        case .unknownLarge:
            return p.name.isEmpty ? "Unknown (\(p.id))" : p.name
        case .system:
            return p.name
        case .other:
            return p.name
        }
    }

    private func extractMLXModelName(_ p: RawProcessInfo) -> String? {
        // Look for --model argument
        for (i, arg) in p.commandLine.enumerated() {
            if (arg == "--model" || arg == "-m"), i + 1 < p.commandLine.count {
                let modelPath = p.commandLine[i + 1]
                return (modelPath as NSString).lastPathComponent
            }
        }
        return nil
    }

    private func extractServiceName(_ p: RawProcessInfo, fallback: String) -> String {
        let cmd = p.commandLine.joined(separator: " ")
        // Try to find a recognizable name in the command
        if cmd.contains("bge") || cmd.contains("BGE") { return "BGE-M3 Embedding" }
        if cmd.contains("sentence_transformers") { return "Sentence Transformers" }
        return fallback
    }

    private func extractAppName(_ p: RawProcessInfo) -> String {
        // Extract "AppName" from "/Applications/AppName.app/Contents/..."
        let components = p.path.split(separator: "/")
        for comp in components {
            if comp.hasSuffix(".app") {
                return String(comp.dropLast(4))
            }
        }
        return p.name
    }
}
