import SwiftUI

/// List of installed Ollama models with loaded/idle status.
struct ServiceListView: View {
    let installedModels: [OllamaInstalledModel]
    let runningModelNames: Set<String>
    let ollamaAvailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("INSTALLED MODELS")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                if ollamaAvailable {
                    HStack(spacing: 4) {
                        Circle().fill(.green).frame(width: 6, height: 6)
                        Text("Ollama")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 4) {
                        Circle().fill(.red).frame(width: 6, height: 6)
                        Text("Ollama offline")
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                    }
                }
            }

            if installedModels.isEmpty && !ollamaAvailable {
                Text("Ollama not running")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(installedModels.prefix(8)) { model in
                    HStack {
                        Text(model.name)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Spacer()

                        Text(String(format: "%.0fGB", model.sizeGB))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)

                        let isLoaded = runningModelNames.contains(model.name)
                        HStack(spacing: 3) {
                            Circle()
                                .fill(isLoaded ? .green : .gray.opacity(0.4))
                                .frame(width: 6, height: 6)
                            Text(isLoaded ? "loaded" : "idle")
                                .font(.system(size: 10))
                                .foregroundStyle(isLoaded ? .green : .secondary)
                        }
                        .frame(width: 55, alignment: .trailing)
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }
}
