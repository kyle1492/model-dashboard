import Foundation

/// HTTP client for Ollama API (localhost:11434).
struct OllamaClient: Sendable {
    let baseURL: URL
    private let session: URLSession

    init(host: String = "127.0.0.1", port: UInt16 = 11434) {
        // Force is safe: this is a well-formed literal URL with controlled inputs
        self.baseURL = URL(string: "http://\(host):\(port)")!
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        // Explicitly disable all proxies (system has proxy configured)
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable: false,
            kCFNetworkProxiesHTTPSEnable: false,
            kCFNetworkProxiesSOCKSEnable: false,
        ] as [AnyHashable: Any]
        self.session = URLSession(configuration: config)
    }

    /// GET /api/ps — running models
    func runningModels() async -> [OllamaRunningModel] {
        guard let data = await get(path: "/api/ps") else { return [] }
        do {
            return try JSONDecoder().decode(OllamaPsResponse.self, from: data).models
        } catch {
            return []
        }
    }

    /// GET /api/tags — installed models
    func installedModels() async -> [OllamaInstalledModel] {
        guard let data = await get(path: "/api/tags") else { return [] }
        do {
            return try JSONDecoder().decode(OllamaTagsResponse.self, from: data).models
        } catch {
            return []
        }
    }

    /// Check if Ollama is reachable
    func isAvailable() async -> Bool {
        await get(path: "/") != nil
    }

    private func get(path: String) async -> Data? {
        let url = baseURL.appendingPathComponent(path)
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            return data
        } catch {
            return nil
        }
    }
}
