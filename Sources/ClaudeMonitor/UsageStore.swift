import Foundation
import Combine
import Darwin
import ClaudeMonitorCore

/// Reads Claude usage published by the status-line bridge and watches its cache.
/// This store never launches Claude Code or performs periodic polling.
@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()

    @Published private(set) var usage: Usage?
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?

    private var directorySource: DispatchSourceFileSystemObject?

    func start() {
        guard directorySource == nil else { return }
        reloadCache()
        startWatchingCache()
    }

    /// Re-read once when the popover opens in case an event arrived while the app
    /// was suspended. Normal updates arrive through the directory watcher.
    func reload() {
        reloadCache()
    }

    private func reloadCache() {
        do {
            if let cached = try UsageCache.read() { acceptIfNewer(cached) }
        } catch {
            if usage == nil { errorMessage = "\(error)" }
        }
    }

    private func acceptIfNewer(_ candidate: Usage) {
        if let lastUpdated, candidate.observedAt < lastUpdated { return }
        usage = candidate
        lastUpdated = candidate.observedAt
        errorMessage = nil
    }

    private func startWatchingCache() {
        guard directorySource == nil else { return }
        do {
            try UsageCache.ensureDirectory()
            let directory = UsageCache.fileURL.deletingLastPathComponent()
            let descriptor = open(directory.path, O_EVTONLY)
            guard descriptor >= 0 else {
                errorMessage = "Could not watch the usage cache directory."
                return
            }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete],
                queue: DispatchQueue.global(qos: .utility)
            )
            source.setEventHandler { [weak self] in
                Task { @MainActor in self?.reloadCache() }
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            directorySource = source
        } catch {
            errorMessage = "\(error)"
        }
    }

    #if DEBUG
    /// Inject a fixed value for snapshot rendering / previews.
    func injectSample(_ usage: Usage) {
        self.usage = usage
        self.lastUpdated = Date()
    }
    #endif

    /// Compact menu-bar label, e.g. "21%" or "—".
    var labelText: String {
        if let p = usage?.sessionPercent { return "\(p)%" }
        return "—"
    }
}
