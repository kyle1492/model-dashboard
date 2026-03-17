import Foundation

/// Generic HTTP health checker for local services.
struct HealthChecker: Sendable {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable: false,
            kCFNetworkProxiesHTTPSEnable: false,
        ] as [AnyHashable: Any]
        self.session = URLSession(configuration: config)
    }

    func check(port: UInt16, paths: [String] = ["/health", "/"]) async -> HealthCheckResult {
        for path in paths {
            guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else { continue }
            let start = ContinuousClock.now
            do {
                let (_, response) = try await session.data(from: url)
                let elapsed = ContinuousClock.now - start
                let ms = Double(elapsed.components.attoseconds) / 1e15
                if let http = response as? HTTPURLResponse, (200...399).contains(http.statusCode) {
                    return HealthCheckResult(isHealthy: true, responseTimeMs: ms, statusCode: http.statusCode)
                }
            } catch {
                continue
            }
        }
        return HealthCheckResult(isHealthy: false, responseTimeMs: 0, statusCode: nil)
    }
}
