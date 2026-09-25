import SwiftUI
import ClaudeMonitorCore

/// The popover: usage ring as the hero, a live "Resets in …" countdown beneath it,
/// and a quiet footer. Nothing else.
struct MenuBarView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var codexStore: CodexStore
    @ObservedObject private var loginItem = LoginItem.shared

    var body: some View {
        VStack(spacing: 16) {
            content
            if let codex = codexStore.usage, !codex.windows.isEmpty {
                Divider()
                CodexSection(usage: codex)
            }
            loginRow
            footer
        }
        .padding(20)
        .frame(width: 232)
        .onAppear {
            store.reload()
            codexStore.refresh()
            loginItem.refresh()
        }
    }

    private var loginRow: some View {
        Toggle(isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.set($0) })) {
            Text("Launch at login")
                .font(.system(size: 12, design: .rounded))
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .tint(Color(red: 0.16, green: 0.63, blue: 0.51))
    }

    @ViewBuilder
    private var content: some View {
        if let usage = store.usage {
            UsageRingView(percent: usage.sessionPercent)
            ResetLabel(usage: usage)
            if let week = usage.weekPercent {
                Divider()
                WeeklyBar(percent: week, resetAt: usage.weekResetAt)
            }
        } else if let err = store.errorMessage {
            placeholder(symbol: "exclamationmark.triangle", title: "Couldn’t read usage")
            Text(err)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        } else {
            placeholder(symbol: "bolt.horizontal.circle",
                        title: "Waiting for usage…")
            Text("Updates after Claude Code responses.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func placeholder(symbol: String, title: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(height: 132)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let updated = store.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit")
        }
        .foregroundStyle(.secondary)
        .font(.system(size: 12))
    }

}

/// Live countdown to the session reset, refreshed each minute.
private struct ResetLabel: View {
    let usage: Usage

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 12))
                Text(text(now: context.date))
                    .font(.system(.subheadline, design: .rounded))
            }
            .foregroundStyle(.secondary)
        }
    }

    private func text(now: Date) -> String {
        "Resets in \(ResetTime.countdown(to: usage.sessionResetAt, from: now))"
    }
}
