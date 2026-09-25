import SwiftUI

/// The signature element: a single ring for the rolling 5-hour window. Its color
/// shifts with urgency (calm → amber → Claude-coral) and the percentage sits at
/// the center in rounded numerals.
struct UsageRingView: View {
    let percent: Int
    var diameter: CGFloat = 132
    var lineWidth: CGFloat = 13

    private var fraction: Double { min(max(Double(percent) / 100, 0), 1) }

    private var tint: Color {
        switch percent {
        case ..<60: return Color(red: 0.16, green: 0.63, blue: 0.51) // teal
        case ..<85: return Color(red: 0.91, green: 0.62, blue: 0.20) // amber
        default:    return Color(red: 0.84, green: 0.31, blue: 0.22) // coral
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: fraction)

            VStack(spacing: 0) {
                Text("\(percent)")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
                Text("% used")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}
