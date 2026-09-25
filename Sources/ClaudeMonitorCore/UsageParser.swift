import Foundation

public struct UsagePanel: Equatable, Sendable {
    public let sessionPercent: Int
    public let sessionReset: String?
    public let timezone: String?
    public let weekPercent: Int?
    public let weekReset: String?
}

public enum UsageParser {
    private static let sessionHeading = "Current\\s*session"
    private static let allModelsWeekHeading = "Current\\s*week\\s*\\(\\s*all\\s*models\\s*\\)"
    private static let anyWeekHeading = "Current\\s*week\\b"

    public static func parse(_ cleaned: String) -> UsagePanel? {
        let text = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard let session = block(in: text, after: sessionHeading, until: anyWeekHeading) else { return nil }
        let week = block(in: text, after: allModelsWeekHeading, until: anyWeekHeading)
        return UsagePanel(
            sessionPercent: session.percent,
            sessionReset: session.reset,
            timezone: session.tz ?? week?.tz,
            weekPercent: week?.percent,
            weekReset: week?.reset
        )
    }

    private struct Block { let percent: Int; let reset: String?; let tz: String? }

    private static func block(in text: String, after heading: String, until nextHeading: String?) -> Block? {
        guard let start = ranges(of: heading, in: text).last?.upperBound else { return nil }
        var region = String(text[start...])
        if let nextHeading, let end = ranges(of: nextHeading, in: region).first?.lowerBound {
            region = String(region[..<end])
        }
        return percentAndReset(in: region)
    }

    private static func percentAndReset(in region: String) -> Block? {
        guard let percent = firstMatch("(\\d{1,3})\\s*%\\s*used", in: region, group: 1)
            .flatMap(Int.init) else { return nil }
        var reset: String?
        var timezone: String?
        if let match = firstTwoGroups("Resets\\s*([^()]+?)\\s*\\(([^)]+)\\)", in: region) {
            reset = match.0.trimmingCharacters(in: .whitespaces)
            timezone = match.1.trimmingCharacters(in: .whitespaces)
        } else if let when = firstMatch("Resets\\s*([^()\\n]+)", in: region, group: 1) {
            reset = when.trimmingCharacters(in: .whitespaces)
        }
        return Block(percent: percent, reset: reset, tz: timezone)
    }

    private static func firstMatch(_ pattern: String, in text: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: group), in: text) else { return nil }
        return String(text[range])
    }

    private static func firstTwoGroups(_ pattern: String, in text: String) -> (String, String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let first = Range(match.range(at: 1), in: text),
              let second = Range(match.range(at: 2), in: text) else { return nil }
        return (String(text[first]), String(text[second]))
    }

    private static func ranges(of pattern: String, in text: String) -> [Range<String.Index>] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text) }
    }
}
