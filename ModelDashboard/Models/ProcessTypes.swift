import Foundation

// MARK: - Process Category

enum ProcessCategory: String, CaseIterable, Sendable {
    case ollamaRuntime      // ollama_llama_server (holds model memory)
    case ollamaPlatform     // ollama main process
    case mlxLM              // Python MLX LM inference
    case embedding          // Python embedding service (BGE-M3 etc)
    case tts                // Python TTS service
    case stt                // Python STT (Whisper etc)
    case imageGeneration    // diffusers, ComfyUI, Stable Diffusion, FLUX, etc.
    case llmRuntime         // llama.cpp, KoboldCPP, vLLM, GPT4All, etc.
    case lmStudio           // LM Studio model worker
    case mlAPI              // ML API server (FastAPI/Flask/uvicorn)
    case userApp            // /Applications/*.app
    case unknownLarge       // >1GB unclassified
    case system             // system processes
    case other              // everything else

    var displayName: String {
        switch self {
        case .ollamaRuntime: "Ollama Model"
        case .ollamaPlatform: "Ollama Platform"
        case .mlxLM: "MLX LM"
        case .embedding: "Embedding"
        case .tts: "TTS"
        case .stt: "STT"
        case .imageGeneration: "Image Generation"
        case .llmRuntime: "LLM Runtime"
        case .lmStudio: "LM Studio"
        case .mlAPI: "ML API"
        case .userApp: "App"
        case .unknownLarge: "Unknown (Large)"
        case .system: "System"
        case .other: "Other"
        }
    }

    var isModel: Bool {
        switch self {
        case .ollamaRuntime, .mlxLM, .llmRuntime, .lmStudio, .embedding, .tts, .stt, .imageGeneration:
            return true
        default:
            return false
        }
    }

    var isService: Bool {
        switch self {
        case .embedding, .tts, .stt, .imageGeneration, .mlAPI:
            return true
        default:
            return false
        }
    }
}

// MARK: - Raw Process Info (from proc_pidinfo)

struct RawProcessInfo: Identifiable, Sendable {
    let id: pid_t  // PID
    let name: String
    let path: String
    let commandLine: [String]
    let memoryBytes: UInt64
    let cpuTimeUser: UInt64    // microseconds
    let cpuTimeSystem: UInt64  // microseconds
    let parentPID: pid_t

    var memoryGB: Double { Double(memoryBytes) / 1_073_741_824 }
    var memoryMB: Double { Double(memoryBytes) / 1_048_576 }
}

// MARK: - Classified Process

struct ClassifiedProcess: Identifiable, Sendable {
    let id: pid_t
    let raw: RawProcessInfo
    let category: ProcessCategory
    var displayName: String  // enriched name (e.g., model name from Ollama API)
    var port: UInt16?
    var serviceHealthy: Bool?

    // Ollama enrichment
    var ollamaModelName: String?
    var ollamaQuantization: String?
    var ollamaSizeVRAM: UInt64?
    var ollamaExpiresAt: Date?

    var expiresInSeconds: TimeInterval? {
        guard let exp = ollamaExpiresAt else { return nil }
        return exp.timeIntervalSinceNow
    }
}
