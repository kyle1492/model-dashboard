import SwiftUI

/// Compact sparkline chart from a ring buffer of values.
struct SparklineView: View {
    let values: [Double]
    var color: Color = .green
    var lineWidth: CGFloat = 1.5

    var body: some View {
        Canvas { context, size in
            guard values.count >= 2 else { return }

            let maxVal = values.max() ?? 1
            let effectiveMax = maxVal > 0 ? maxVal : 1

            let stepX = size.width / CGFloat(values.count - 1)

            var path = Path()
            for (i, value) in values.enumerated() {
                let x = CGFloat(i) * stepX
                let y = size.height - (CGFloat(value / effectiveMax) * size.height)
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            context.stroke(path, with: .color(color), lineWidth: lineWidth)

            // Fill under curve with gradient
            var fillPath = path
            fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
            fillPath.addLine(to: CGPoint(x: 0, y: size.height))
            fillPath.closeSubpath()

            context.fill(fillPath, with: .linearGradient(
                Gradient(colors: [color.opacity(0.3), color.opacity(0.05)]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: size.height)
            ))
        }
    }
}
