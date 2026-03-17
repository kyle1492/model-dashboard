import SwiftUI

/// Circular gauge ring showing a percentage.
struct GaugeRingView: View {
    let value: Double // 0.0 - 1.0
    var label: String = ""
    var size: CGFloat = 60
    var lineWidth: CGFloat = 6
    var color: Color { gaugeColor(value) }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: lineWidth)

            // Value ring
            Circle()
                .trim(from: 0, to: min(1, max(0, value)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: value)

            // Center text
            VStack(spacing: 0) {
                Text("\(Int(value * 100))")
                    .font(.system(size: size * 0.28, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                if !label.isEmpty {
                    Text(label)
                        .font(.system(size: size * 0.14))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
    }

    private func gaugeColor(_ v: Double) -> Color {
        if v < 0.5 { return .green }
        if v < 0.8 { return .yellow }
        return .red
    }
}
