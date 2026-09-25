import Foundation

/// Decodes Claude Code status-line JSON and persists the latest rate-limit snapshot.
public enum UsageCache {
    public enum CacheError: Error, CustomStringConvertible {
        case unsupportedSchema(Int)

        public var description: String {
            switch self {
            case .unsupportedSchema(let version):
                return "Unsupported usage-cache schema version \(version)."
            }
        }
    }

    public static var directoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ClaudeMonitor", isDirectory: true)
    }

    public static var fileURL: URL {
        if let override = ProcessInfo.processInfo.environment["CLAUDE_MONITOR_CACHE_PATH"],
           !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return directoryURL.appendingPathComponent("usage.json")
    }

    public static func ensureDirectory(for url: URL = fileURL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    /// Returns nil before the first Claude response has supplied subscriber limits.
    public static func usage(fromStatusLine data: Data, observedAt: Date = Date()) throws -> Usage? {
        let envelope = try JSONDecoder().decode(StatusLineEnvelope.self, from: data)
        guard let fiveHour = envelope.rateLimits?.fiveHour,
              let fiveHourPercent = fiveHour.usedPercentage,
              let fiveHourReset = fiveHour.resetsAt else { return nil }
        let sevenDay = envelope.rateLimits?.sevenDay
        let weekPercent = sevenDay?.usedPercentage.map(roundedPercent)
        let weekReset = sevenDay?.resetsAt.map { Date(timeIntervalSince1970: $0) }
        return Usage(
            sessionPercent: roundedPercent(fiveHourPercent),
            sessionResetAt: Date(timeIntervalSince1970: fiveHourReset),
            weekPercent: weekPercent,
            weekResetAt: weekPercent == nil ? nil : weekReset,
            observedAt: observedAt
        )
    }

    public static func write(_ usage: Usage, to url: URL = fileURL) throws {
        try ensureDirectory(for: url)
        let record = CacheRecord(usage: usage)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(record).write(to: url, options: .atomic)
    }

    public static func read(from url: URL = fileURL) throws -> Usage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let record = try JSONDecoder().decode(CacheRecord.self, from: Data(contentsOf: url))
        guard record.schemaVersion == 1 else { throw CacheError.unsupportedSchema(record.schemaVersion) }
        return record.usage
    }

    private static func roundedPercent(_ value: Double) -> Int {
        min(max(Int(value.rounded()), 0), 100)
    }
}

private struct StatusLineEnvelope: Decodable {
    let rateLimits: RateLimits?

    enum CodingKeys: String, CodingKey { case rateLimits = "rate_limits" }
}

private struct RateLimits: Decodable {
    let fiveHour: StatusLineLimitWindow?
    let sevenDay: StatusLineLimitWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

private struct StatusLineLimitWindow: Decodable {
    let usedPercentage: Double?
    let resetsAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }
}

private struct CacheLimitWindow: Codable {
    let usedPercentage: Double
    let resetsAt: TimeInterval

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }
}

private struct CacheRecord: Codable {
    let schemaVersion: Int
    let observedAt: TimeInterval
    let fiveHour: CacheLimitWindow
    let sevenDay: CacheLimitWindow?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case observedAt = "observed_at"
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }

    init(usage: Usage) {
        schemaVersion = 1
        observedAt = usage.observedAt.timeIntervalSince1970
        fiveHour = CacheLimitWindow(
            usedPercentage: Double(usage.sessionPercent),
            resetsAt: usage.sessionResetAt.timeIntervalSince1970
        )
        if let percent = usage.weekPercent, let reset = usage.weekResetAt {
            sevenDay = CacheLimitWindow(
                usedPercentage: Double(percent),
                resetsAt: reset.timeIntervalSince1970
            )
        } else {
            sevenDay = nil
        }
    }

    var usage: Usage {
        Usage(
            sessionPercent: min(max(Int(fiveHour.usedPercentage.rounded()), 0), 100),
            sessionResetAt: Date(timeIntervalSince1970: fiveHour.resetsAt),
            weekPercent: sevenDay.map { min(max(Int($0.usedPercentage.rounded()), 0), 100) },
            weekResetAt: sevenDay.map { Date(timeIntervalSince1970: $0.resetsAt) },
            observedAt: Date(timeIntervalSince1970: observedAt)
        )
    }
}
