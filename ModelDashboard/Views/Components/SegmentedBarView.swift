import SwiftUI

/// Horizontal segmented bar (e.g., memory breakdown).
struct SegmentedBarView: View {
    let segments: [Segment]
    let totalValue: Double
    var height: CGFloat = 28

    struct Segment: Identifiable {
        let id = UUID()
        let label: String
        let value: Double
        let color: Color
        var isStriped: Bool = false
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(segments) { seg in
                    let fraction = totalValue > 0 ? seg.value / totalValue : 0
                    let width = max(0, fraction * geo.size.width)

                    if width > 2 {
                        ZStack {
                            Rectangle()
                                .fill(seg.color)
                            if seg.isStriped {
                                StripedPattern()
                                    .clipShape(Rectangle())
                            }
                        }
                        .frame(width: width)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .frame(height: height)
    }
}

/// Diagonal stripe overlay for inactive/cache memory.
struct StripedPattern: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 6
            let color = Color.black.opacity(0.3)
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(path, with: .color(color), lineWidth: 1.5)
                x += spacing
            }
        }
    }
}
