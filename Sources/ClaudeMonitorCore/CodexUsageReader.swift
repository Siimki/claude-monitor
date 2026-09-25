import Foundation

/// Reads the freshest Codex rate-limit snapshot from the CLI's rollout logs.
///
/// Codex writes a `token_count` event into `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`
/// after each response. Newer builds attach a populated `rate_limits` object; some
/// builds/modes leave it `null`. We scan the most recently modified rollout files and
/// keep the event with the latest internal timestamp whose `rate_limits` is populated.
public enum CodexUsageReader {
    /// A completed scan plus the file-state fingerprint that produced it.
    public struct ScanResult: Sendable {
        public let usage: CodexUsage?
        public let fingerprint: String
    }

    public enum ReadError: Error, CustomStringConvertible {
        case noSessionsDirectory
        case noRateLimitData

        public var description: String {
            switch self {
            case .noSessionsDirectory: return "No Codex sessions directory found (~/.codex/sessions)."
            case .noRateLimitData: return "No Codex rate-limit data in recent sessions."
            }
        }
    }

    /// `$CODEX_HOME/sessions`, else `~/.codex/sessions`. `CODEX_SESSIONS_DIR` overrides
    /// both (used by the deterministic checks).
    public static var sessionsDirectory: URL {
        let env = ProcessInfo.processInfo.environment
        if let override = env["CODEX_SESSIONS_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let home = env["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        return home.appendingPathComponent("sessions", isDirectory: true)
    }

    /// Newest populated snapshot, or nil when Codex isn't installed / has no usable data.
    public static func read(scanningNewest limit: Int = 12) -> CodexUsage? {
        scan(scanningNewest: limit)?.usage
    }

    /// Scans only when one of the candidate rollout files has changed. Each file is
    /// searched backward from its tail, avoiding a full read in the common case.
    public static func scan(scanningNewest limit: Int = 12,
                            changedFrom previousFingerprint: String? = nil) -> ScanResult? {
        let files = recentRolloutFiles(limit: limit)
        let fingerprint = files.map(\.fingerprintComponent).joined(separator: "\n")
        if fingerprint == previousFingerprint { return nil }

        var best: (timestamp: Date, usage: CodexUsage)?
        for file in files {
            guard let candidate = latestSnapshot(in: file.url) else { continue }
            if best == nil || candidate.timestamp > best!.timestamp {
                best = candidate
            }
        }
        return ScanResult(usage: best?.usage, fingerprint: fingerprint)
    }

    /// Rollout files under the sessions tree, newest modification first, capped at `limit`.
    private static func recentRolloutFiles(limit: Int) -> [RolloutFile] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        ) else { return [] }

        var found: [RolloutFile] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasPrefix("rollout-"),
                  url.pathExtension == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            found.append(RolloutFile(
                url: url,
                modified: values?.contentModificationDate ?? .distantPast,
                size: values?.fileSize ?? 0
            ))
        }
        return Array(found.sorted { $0.modified > $1.modified }.prefix(limit))
    }

    /// Rollout events are append-only, so the last populated rate-limit event in a
    /// file is its freshest one. Start with 256 KiB and expand only when necessary.
    private static func latestSnapshot(in url: URL) -> (timestamp: Date, usage: CodexUsage)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let fileSize = try? handle.seekToEnd(), fileSize > 0 else { return nil }

        var length = min(fileSize, 256 * 1024)
        while length > 0 {
            let offset = fileSize - length
            do {
                try handle.seek(toOffset: offset)
                guard let data = try handle.read(upToCount: Int(length)), !data.isEmpty else {
                    return nil
                }
                var text = String(decoding: data, as: UTF8.self)
                if offset > 0, let newline = text.firstIndex(of: "\n") {
                    text.removeSubrange(...newline) // discard the partial first line
                }

                for line in text.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
                    guard let candidate = snapshot(from: line) else { continue }
                    return candidate
                }
            } catch {
                return nil
            }

            if length == fileSize { break }
            length = min(fileSize, length * 4)
        }
        return nil
    }

    private static func snapshot(from line: Substring) -> (timestamp: Date, usage: CodexUsage)? {
        guard line.contains("\"rate_limits\""),
              let data = line.data(using: .utf8),
              let entry = try? JSONDecoder().decode(RolloutEntry.self, from: data),
              entry.payload?.type == "token_count",
              let limits = entry.payload?.rateLimits,
              let observedAt = entry.date else { return nil }
        let windows = limits.windows(observedAt: observedAt)
        guard !windows.isEmpty else { return nil }
        return (observedAt, CodexUsage(
            windows: windows,
            planType: limits.planType,
            observedAt: observedAt
        ))
    }
}

private struct RolloutFile {
    let url: URL
    let modified: Date
    let size: Int

    var fingerprintComponent: String {
        "\(url.path)|\(size)|\(modified.timeIntervalSinceReferenceDate)"
    }
}

// MARK: - Rollout JSON decoding

private struct RolloutEntry: Decodable {
    let timestamp: String?
    let payload: Payload?

    /// Codex timestamps are ISO-8601 with fractional seconds (e.g. 2026-07-20T12:34:30.587Z).
    var date: Date? {
        guard let timestamp else { return nil }
        return RolloutEntry.formatter.date(from: timestamp)
            ?? RolloutEntry.fallbackFormatter.date(from: timestamp)
    }

    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let fallbackFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    struct Payload: Decodable {
        let type: String?
        let rateLimits: RateLimits?
        enum CodingKeys: String, CodingKey { case type; case rateLimits = "rate_limits" }
    }
}

private struct RateLimits: Decodable {
    let primary: Window?
    let secondary: Window?
    let planType: String?

    enum CodingKeys: String, CodingKey {
        case primary, secondary
        case planType = "plan_type"
    }

    func windows(observedAt: Date) -> [CodexWindow] {
        [primary, secondary].compactMap { $0?.codexWindow(observedAt: observedAt) }
    }
}

private struct Window: Decodable {
    let usedPercent: Double?
    let windowMinutes: Int?
    let resetsAt: Double?          // absolute unix seconds (Team/monthly builds)
    let resetsInSeconds: Double?   // relative seconds from the event (5h/weekly builds)

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
        case resetsInSeconds = "resets_in_seconds"
    }

    func codexWindow(observedAt: Date) -> CodexWindow? {
        guard let usedPercent, let windowMinutes else { return nil }
        let reset: Date
        if let resetsAt {
            reset = Date(timeIntervalSince1970: resetsAt)
        } else if let resetsInSeconds {
            reset = observedAt.addingTimeInterval(resetsInSeconds)
        } else {
            return nil
        }
        return CodexWindow(
            usedPercent: min(max(Int(usedPercent.rounded()), 0), 100),
            resetsAt: reset,
            windowMinutes: windowMinutes
        )
    }
}
