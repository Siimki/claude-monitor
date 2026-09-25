import Foundation
import Combine
import ClaudeMonitorCore

/// Reads Codex usage from its rollout logs at launch and when the popover opens.
/// A file fingerprint makes repeated opens free when the logs have not changed.
@MainActor
final class CodexStore: ObservableObject {
    static let shared = CodexStore()

    @Published private(set) var usage: CodexUsage?
    @Published private(set) var lastUpdated: Date?

    private var fingerprint: String?
    private var isRefreshing = false

    func start() {
        refresh()
    }

    /// Reads the newest snapshot off the main thread; keeps the previous value if the
    /// scan finds nothing (e.g. a build that logs `rate_limits: null`).
    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let previousFingerprint = fingerprint
        Task.detached(priority: .utility) {
            let scan = CodexUsageReader.scan(changedFrom: previousFingerprint)
            await MainActor.run {
                self.isRefreshing = false
                guard let scan else { return }
                self.fingerprint = scan.fingerprint
                guard let scanned = scan.usage else { return }
                if let current = self.usage, scanned.observedAt <= current.observedAt { return }
                self.usage = scanned
                self.lastUpdated = scanned.observedAt
            }
        }
    }

    #if DEBUG
    func injectSample(_ usage: CodexUsage) {
        self.usage = usage
        self.lastUpdated = usage.observedAt
    }
    #endif
}
