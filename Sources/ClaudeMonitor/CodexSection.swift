import SwiftUI
import ClaudeMonitorCore

/// Codex usage beneath the Claude ring: one slim bar per rate-limit window. Renders
/// nothing until Codex data exists, so Claude-only users see the popover unchanged.
struct CodexSection: View {
    let usage: CodexUsage

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Text("Codex")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            ForEach(usage.windows, id: \.windowMinutes) { window in
                CodexWindowBar(window: window)
            }
        }
    }
}

/// A single Codex window: title (5-hour / Weekly / Monthly), percent, bar, and a live
/// reset countdown. Mirrors `WeeklyBar` so the two providers read as one system.
private struct CodexWindowBar: View {
    let window: CodexWindow

    private var fraction: Double { min(max(Double(window.usedPercent) / 100, 0), 1) }

    private var tint: Color {
        switch window.usedPercent {
        case ..<60: return Color(red: 0.16, green: 0.63, blue: 0.51)
        case ..<85: return Color(red: 0.91, green: 0.62, blue: 0.20)
        default:    return Color(red: 0.84, green: 0.31, blue: 0.22)
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(window.label)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(window.usedPercent)%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(tint)
                        .frame(width: window.usedPercent == 0 ? 0 : max(4, geo.size.width * fraction))
                        .animation(.easeInOut(duration: 0.6), value: fraction)
                }
            }
            .frame(height: 6)

            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text("Resets in \(ResetTime.countdownLong(to: window.resetsAt, from: context.date))")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
