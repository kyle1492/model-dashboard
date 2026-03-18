import SwiftUI

/// Card for a single running model/service.
struct ModelCardView: View {
    let process: ClassifiedProcess

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: name + category badge
            HStack {
                Text(process.displayName)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                categoryBadge
            }

            // Details line
            HStack(spacing: 8) {
                // Memory
                Text(formatMemory(process.raw.memoryBytes))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.green)

                // Quantization
                if let quant = process.ollamaQuantization {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(quant)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Port + health indicator
                if let port = process.port {
                    HStack(spacing: 4) {
                        Text(":\(port)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                        if let healthy = process.serviceHealthy {
                            Circle()
                                .fill(healthy ? .green : .red)
                                .frame(width: 6, height: 6)
                            Text(healthy ? "UP" : "DOWN")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(healthy ? .green : .red)
                        }
                    }
                }
            }

            // Ollama expiry countdown
            if let seconds = process.expiresInSeconds, seconds > 0 {
                HStack(spacing: 4) {
                    Text("Ollama")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("· expires \(formatDuration(seconds))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.yellow)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(borderColor, lineWidth: 1)
                )
        )
    }

    private var categoryBadge: some View {
        Text(process.category.displayName)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    private var borderColor: Color {
        switch process.category {
        case .ollamaRuntime: .green.opacity(0.3)
        case .embedding: .blue.opacity(0.3)
        case .mlxLM: .purple.opacity(0.3)
        case .llmRuntime: .cyan.opacity(0.3)
        case .lmStudio: .indigo.opacity(0.3)
        case .imageGeneration: .pink.opacity(0.3)
        case .unknownLarge: .red.opacity(0.3)
        default: .white.opacity(0.08)
        }
    }

    private func formatMemory(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 {
            return String(format: "%.1fGB", gb)
        }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.0fMB", mb)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins > 0 {
            return "\(mins):\(String(format: "%02d", secs))"
        }
        return "\(secs)s"
    }
}
