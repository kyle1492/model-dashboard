import Foundation

// MARK: - /api/ps response

struct OllamaPsResponse: Codable, Sendable {
    let models: [OllamaRunningModel]
}

struct OllamaRunningModel: Codable, Sendable {
    let name: String
    let model: String
    let size: UInt64
    let digest: String
    let details: OllamaModelDetails
    let expires_at: String
    let size_vram: UInt64

    var expiresAt: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: expires_at)
            ?? ISO8601DateFormatter().date(from: expires_at)
    }

    /// Extract quantization level from details
    var quantization: String? {
        details.quantization_level
    }
}

struct OllamaModelDetails: Codable, Sendable {
    let parent_model: String?
    let format: String?
    let family: String?
    let families: [String]?
    let parameter_size: String?
    let quantization_level: String?
}

// MARK: - /api/tags response

struct OllamaTagsResponse: Codable, Sendable {
    let models: [OllamaInstalledModel]
}

struct OllamaInstalledModel: Codable, Sendable, Identifiable {
    let name: String
    let model: String
    let modified_at: String
    let size: UInt64
    let digest: String
    let details: OllamaModelDetails

    var id: String { name }
    var sizeGB: Double { Double(size) / 1_073_741_824 }
}
