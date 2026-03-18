import Foundation

/// Rule-based classifier using keyword tables — no path dependency.
/// Adding support for a new framework = adding one line to the keyword table.
struct ProcessClassifier: Sendable {

    // MARK: - Keyword → Category tables

    /// Keywords matched against the full command line (case-insensitive).
    /// Order within each category doesn't matter; categories are checked
    /// in priority order (model categories before generic ones).
    /// More specific keywords should come before broader ones.
    private static let keywordRules: [(keyword: String, category: ProcessCategory)] = [
        // ── LLM runtimes ──────────────────────────────────────────
        // Ollama model runners (the serve process is handled separately by name)
        ("ollama_llama_server",  .ollamaRuntime),
        ("ollama runner",        .ollamaRuntime),

        // MLX LM (Apple Silicon native)
        ("mlx_lm",              .mlxLM),
        ("mlx-lm",              .mlxLM),
        ("mlx_vlm",             .mlxLM),       // MLX vision-language models

        // LM Studio model worker (the one that actually loads weights)
        ("llmworker",           .lmStudio),

        // llama.cpp standalone (match binary names, not library paths)
        ("llama-server",        .llmRuntime),
        ("llama_server",        .llmRuntime),
        ("llama-cli",           .llmRuntime),

        // KoboldCPP
        ("koboldcpp",           .llmRuntime),

        // vLLM
        ("vllm",                .llmRuntime),

        // GPT4All
        ("gpt4all",             .llmRuntime),

        // LocalAI
        ("localai",             .llmRuntime),

        // ExLlamaV2
        ("exllamav2",           .llmRuntime),
        ("exllama",             .llmRuntime),

        // text-generation-webui (oobabooga)
        ("text-generation-webui", .llmRuntime),

        // HuggingFace TGI
        ("text-generation-launcher", .llmRuntime),

        // ── Image generation ──────────────────────────────────────
        ("comfyui",             .imageGeneration),
        ("stable-diffusion",    .imageGeneration),
        ("stable_diffusion",    .imageGeneration),
        ("sd_webui",            .imageGeneration),
        ("sd-webui",            .imageGeneration),
        ("diffusers",           .imageGeneration),
        ("diffuser",            .imageGeneration),
        ("mflux",               .imageGeneration),
        ("invokeai",            .imageGeneration),
        ("mochi-diffusion",     .imageGeneration),
        ("draw-things",         .imageGeneration),
        ("qwen-image",          .imageGeneration),
        ("qwen_image",          .imageGeneration),
        ("fooocus",             .imageGeneration),

        // ── Embedding ─────────────────────────────────────────────
        ("sentence_transformers", .embedding),
        ("sentence-transformers", .embedding),
        ("text-embeddings-inference", .embedding),
        ("embedding",           .embedding),
        ("embed_",              .embedding),   // embed_sentences, embed_text, etc.
        ("bge-m3",              .embedding),
        ("bge_m3",              .embedding),

        // ── TTS ───────────────────────────────────────────────────
        ("edge-tts",            .tts),
        ("coqui",               .tts),
        ("cosyvoice",           .tts),
        ("f5_tts",              .tts),
        ("f5-tts",              .tts),
        ("piper-tts",           .tts),
        ("piper --model",       .tts),
        ("tortoise-tts",        .tts),
        ("qwen3-tts",           .tts),
        ("qwen_tts",            .tts),

        // ── STT ───────────────────────────────────────────────────
        ("whisper",             .stt),
        ("faster_whisper",      .stt),
        ("faster-whisper",      .stt),
        ("whisperx",            .stt),
        ("whisperkit",          .stt),
    ]

    /// Process names that are always system — fast Set lookup.
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

    // MARK: - Public API

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

    // MARK: - Classification logic

    private func determineCategory(_ p: RawProcessInfo) -> ProcessCategory {
        // 1. System processes (fast path)
        if p.id <= 1 { return .system }
        if Self.systemProcessNames.contains(p.name) { return .system }
        if Self.systemPathPrefixes.contains(where: { p.path.hasPrefix($0) }) { return .system }

        // 2. Ollama platform process (the "serve" daemon, not model runner)
        if p.name == "ollama" {
            let cmdJoined = p.commandLine.joined(separator: " ")
            if !cmdJoined.contains("runner") {
                return .ollamaPlatform
            }
        }

        // 3. Keyword scan — matches against full command line
        let cmdLower = p.commandLine.joined(separator: " ").lowercased()
        for rule in Self.keywordRules {
            if cmdLower.contains(rule.keyword) {
                return rule.category
            }
        }

        // 4. Python ML API servers (broad match, after specific ML keywords)
        if p.name.hasPrefix("python") || p.name.hasPrefix("Python") {
            if cmdLower.contains("uvicorn") || cmdLower.contains("fastapi") ||
               cmdLower.contains("flask") || cmdLower.contains("gunicorn") {
                return .mlAPI
            }
        }

        // 5. User apps
        if p.path.contains("/Applications/") && p.path.contains(".app/") {
            return .userApp
        }

        // 6. Unknown large process (>1GB)
        if p.memoryBytes > 1_073_741_824 { return .unknownLarge }

        // 7. Everything else
        return .other
    }

    // MARK: - Display names

    private func displayName(for p: RawProcessInfo, category: ProcessCategory) -> String {
        switch category {
        case .ollamaRuntime:
            return "Ollama Model" // enriched later by ServiceEnricher
        case .ollamaPlatform:
            return "Ollama"
        case .mlxLM:
            return extractModelArg(p) ?? "MLX LM"
        case .llmRuntime:
            return extractLLMName(p)
        case .lmStudio:
            return "LM Studio Model"
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

    // MARK: - Name extraction helpers

    /// Extract --model / -m argument value (last path component).
    private func extractModelArg(_ p: RawProcessInfo) -> String? {
        for (i, arg) in p.commandLine.enumerated() {
            if (arg == "--model" || arg == "-m"), i + 1 < p.commandLine.count {
                let modelPath = p.commandLine[i + 1]
                return (modelPath as NSString).lastPathComponent
            }
        }
        return nil
    }

    /// Build display name for generic LLM runtimes (llama.cpp, koboldcpp, etc.)
    private func extractLLMName(_ p: RawProcessInfo) -> String {
        // Try model arg first
        if let model = extractModelArg(p) { return model }

        // Fall back to recognizable binary name
        let cmd = p.commandLine.first ?? p.name
        if cmd.contains("llama-server") || cmd.contains("llama_server") { return "llama.cpp Server" }
        if cmd.contains("koboldcpp") { return "KoboldCPP" }
        if cmd.contains("vllm") { return "vLLM" }
        if cmd.contains("gpt4all") { return "GPT4All" }
        if cmd.contains("localai") { return "LocalAI" }
        if cmd.contains("exllama") { return "ExLlamaV2" }
        return "LLM Runtime"
    }

    private func extractServiceName(_ p: RawProcessInfo, fallback: String) -> String {
        let cmd = p.commandLine.joined(separator: " ")
        if cmd.contains("bge") || cmd.contains("BGE") { return "BGE-M3 Embedding" }
        if cmd.contains("sentence_transformers") { return "Sentence Transformers" }
        return fallback
    }

    private func extractAppName(_ p: RawProcessInfo) -> String {
        let components = p.path.split(separator: "/")
        for comp in components {
            if comp.hasSuffix(".app") {
                return String(comp.dropLast(4))
            }
        }
        return p.name
    }
}
