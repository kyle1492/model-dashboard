import Foundation

struct ServiceStatus: Identifiable, Sendable {
    let id: String  // "host:port"
    let port: UInt16
    let pid: pid_t
    let processName: String
    var isHealthy: Bool
    var lastChecked: Date
    var responseTimeMs: Double?
}

struct HealthCheckResult: Sendable {
    let isHealthy: Bool
    let responseTimeMs: Double
    let statusCode: Int?
}
