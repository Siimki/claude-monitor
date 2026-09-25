import Foundation

/// Formats the absolute reset timestamps supplied by Claude Code's status-line data.
public enum ResetTime {
    private static let months: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
    ]

    /// Converts reset labels from `/usage` into absolute dates for the shared cache model.
    public static func nextReset(when: String?, timezone: String?, now: Date) -> Date? {
        guard let when else { return nil }
        let timeZone = timezone.flatMap(TimeZone.init(identifier:)) ?? TimeZone.current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let value = when.lowercased().trimmingCharacters(in: .whitespaces)

        if let match = match(
            "^([a-z]{3,})\\s*(\\d{1,2})\\s*,?\\s*a?\\s*t?\\s*(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)$",
            value
        ), let month = months[String((match[1] ?? "").prefix(3))],
           let (hour, minute) = clockHour(match[3], match[4], match[5]) {
            var components = DateComponents()
            components.year = calendar.component(.year, from: now)
            components.month = month
            components.day = Int(match[2] ?? "1") ?? 1
            components.hour = hour
            components.minute = minute
            guard var date = calendar.date(from: components) else { return nil }
            if date < now, calendar.component(.month, from: now) == 12, month == 1 {
                components.year! += 1
                date = calendar.date(from: components) ?? date
            }
            return date
        }

        if let match = match("^(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)$", value),
           let (hour, minute) = clockHour(match[1], match[2], match[3]) {
            var components = calendar.dateComponents([.year, .month, .day], from: now)
            components.hour = hour
            components.minute = minute
            components.second = 0
            guard let today = calendar.date(from: components) else { return nil }
            return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today)
        }
        return nil
    }

    /// "1h 23m", "12m", or "now" — a compact countdown to `reset` from `now`.
    public static func countdown(to reset: Date, from now: Date) -> String {
        let secs = Int(reset.timeIntervalSince(now))
        if secs <= 0 { return "now" }
        let mins = secs / 60
        if mins < 1 { return "<1m" }
        let (h, m) = (mins / 60, mins % 60)
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    /// Like `countdown`, but collapses to days for long ranges: "3d 5h", "2d", "4h 10m".
    public static func countdownLong(to reset: Date, from now: Date) -> String {
        let secs = Int(reset.timeIntervalSince(now))
        if secs <= 0 { return "now" }
        let totalHours = secs / 3600
        if totalHours >= 24 {
            let (d, h) = (totalHours / 24, totalHours % 24)
            return h > 0 ? "\(d)d \(h)h" : "\(d)d"
        }
        return countdown(to: reset, from: now)
    }

    private static func clockHour(_ hourString: Substring?, _ minuteString: Substring?,
                                  _ meridiem: Substring?) -> (Int, Int)? {
        guard var hour = Int(hourString ?? ""), (1...12).contains(hour),
              let minute = Int(minuteString ?? "0"), (0...59).contains(minute) else { return nil }
        let isPM = (meridiem ?? "") == "pm"
        if isPM, hour != 12 { hour += 12 }
        if !isPM, hour == 12 { hour = 0 }
        return (hour, minute)
    }

    private static func match(_ pattern: String, _ text: String) -> [Substring?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        return (0..<result.numberOfRanges).map { index in
            Range(result.range(at: index), in: text).map { text[$0] }
        }
    }
}
