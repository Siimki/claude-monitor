import SwiftUI
import ClaudeMonitorCore

/// Secondary indicator for the weekly (all-models) limit: a slim bar so it reads as
/// supporting info beneath the session ring, never competing with it.
struct WeeklyBar: View {
    let percent: Int
    let resetAt: Date?

    private var fraction: Double { min(max(Double(percent) / 100, 0), 1) }

    private var tint: Color {
        switch percent {
        case ..<60: return Color(red: 0.16, green: 0.63, blue: 0.51)
        case ..<85: return Color(red: 0.91, green: 0.62, blue: 0.20)
        default:    return Color(red: 0.84, green: 0.31, blue: 0.22)
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("This week")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(percent)%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(tint)
                        .frame(width: percent == 0 ? 0 : max(4, geo.size.width * fraction))
                        .animation(.easeInOut(duration: 0.6), value: fraction)
                }
            }
            .frame(height: 6)

            if let resetAt {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text("Resets in \(ResetTime.countdownLong(to: resetAt, from: context.date))")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
