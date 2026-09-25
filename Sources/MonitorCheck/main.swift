import Foundation
import ClaudeMonitorCore

if CommandLine.arguments.contains("codex-live") {
    if let usage = CodexUsageReader.read() {
        print("CODEX LIVE OK → " + usage.windows
            .map { "\($0.label) \($0.usedPercent)%" }.joined(separator: ", ")
            + (usage.planType.map { " (\($0))" } ?? ""))
        exit(0)
    }
    print("CODEX LIVE → no rate-limit data found in recent sessions")
    exit(1)
}

var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    let passed = condition()
    print("\(passed ? "✓" : "✗") \(name)")
    if !passed { failures += 1 }
}

let observed = Date(timeIntervalSince1970: 1_789_031_400)
let statusLine = Data(#"""
{
  "session_id": "test-session",
  "rate_limits": {
    "five_hour": { "used_percentage": 23.5, "resets_at": 1789038000 },
    "seven_day": { "used_percentage": 41.2, "resets_at": 1789466400 }
  }
}
"""#.utf8)

do {
    let usage = try UsageCache.usage(fromStatusLine: statusLine, observedAt: observed)
    check(usage?.sessionPercent == 24, "five-hour percentage rounds to 24")
    check(usage?.weekPercent == 41, "seven-day percentage rounds to 41")
    check(usage?.sessionResetAt == Date(timeIntervalSince1970: 1_789_038_000),
          "five-hour reset timestamp decoded")
    check(usage?.weekResetAt == Date(timeIntervalSince1970: 1_789_466_400),
          "seven-day reset timestamp decoded")
    check(usage?.observedAt == observed, "observation timestamp retained")

    let tempDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("claude-monitor-check-\(UUID().uuidString)", isDirectory: true)
    let cache = tempDirectory.appendingPathComponent("usage.json")
    if let usage { try UsageCache.write(usage, to: cache) }
    let roundTrip = try UsageCache.read(from: cache)
    check(roundTrip == usage, "cache write/read round trip")
    try? FileManager.default.removeItem(at: tempDirectory)
} catch {
    check(false, "status-line decode and cache round trip: \(error)")
}

let beforeFirstResponse = Data(#"{"session_id":"new-session"}"#.utf8)
do {
    let usage = try UsageCache.usage(fromStatusLine: beforeFirstResponse)
    check(usage == nil,
          "missing rate limits waits for first response")
} catch {
    check(false, "missing rate limits decode: \(error)")
}

let clamped = Data(#"""
{"rate_limits":{"five_hour":{"used_percentage":108.4,"resets_at":1789038000}}}
"""#.utf8)
do {
    let usage = try UsageCache.usage(fromStatusLine: clamped)
    check(usage?.sessionPercent == 100,
          "percentage clamps to 100")
} catch {
    check(false, "clamped percentage decode: \(error)")
}

let now = Date(timeIntervalSince1970: 1_000_000)
check(ResetTime.countdown(to: now.addingTimeInterval(59 * 60), from: now) == "59m",
      "short countdown")
check(ResetTime.countdown(to: now.addingTimeInterval(2 * 3600 + 5 * 60), from: now) == "2h 5m",
      "hour countdown")
check(ResetTime.countdownLong(to: now.addingTimeInterval(3 * 24 * 3600 + 5 * 3600), from: now) == "3d 5h",
      "weekly countdown")
check(ResetTime.countdown(to: now, from: now) == "now", "elapsed countdown")

let panelText = """
Current session
23% used
Resets 2pm (Europe/Tallinn)
Current week (all models)
41% used
Resets Jul 19 at 6pm (Europe/Tallinn)
"""
let panel = UsageParser.parse(panelText)
check(panel?.sessionPercent == 23, "PTY panel session percentage")
check(panel?.weekPercent == 41, "PTY panel weekly percentage")
check(panel?.timezone == "Europe/Tallinn", "PTY panel timezone")

let terminalOutput = "\u{1B}[2J\u{1B}[H" + panelText
let replayed = AnsiCleaner.clean(terminalOutput)
check(UsageParser.parse(replayed) == panel, "ANSI terminal replay preserves usage panel")
let charsetDesignated = AnsiCleaner.clean("\u{1B}(B" + panelText)
check(UsageParser.parse(charsetDesignated) == panel, "ANSI character-set escape does not leak text")

let modelSpecificWeek = panelText + "\nCurrent week (Fable)\n87% used\n"
check(UsageParser.parse(modelSpecificWeek)?.weekPercent == 41,
      "all-model weekly limit wins over model-specific limit")

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "Europe/Tallinn")!
let fixedNow = calendar.date(from: DateComponents(
    year: 2026, month: 7, day: 13, hour: 11, minute: 0
))!
let reset = ResetTime.nextReset(when: "2pm", timezone: "Europe/Tallinn", now: fixedNow)
check(reset.map { ResetTime.countdown(to: $0, from: fixedNow) } == "3h 0m",
      "PTY reset label converts to absolute timestamp")
let compactReset = ResetTime.nextReset(
    when: "Jul19at6pm", timezone: "Europe/Tallinn", now: fixedNow
)
check(compactReset.map { ResetTime.countdownLong(to: $0, from: fixedNow) } == "6d 7h",
      "collapsed weekly reset label converts to absolute timestamp")

// Codex rollout parsing: an absolute-reset (monthly) window and a relative-reset
// (5-hour) window, each in its own rollout file, newest wins.
let codexDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("codex-check-\(UUID().uuidString)/2026/07/20", isDirectory: true)
try? FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
let monthly = #"""
{"timestamp":"2026-07-20T10:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":55.0,"window_minutes":43800,"resets_at":1787161549},"secondary":null,"plan_type":"team"}}}
"""#
let fiveHour = #"""
{"timestamp":"2026-07-20T12:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":12.0,"window_minutes":299,"resets_in_seconds":3600},"secondary":{"used_percent":40.0,"window_minutes":10080,"resets_in_seconds":200000},"plan_type":"plus"}}}
"""#
try? monthly.write(to: codexDir.appendingPathComponent("rollout-a.jsonl"), atomically: true, encoding: .utf8)
try? fiveHour.write(to: codexDir.appendingPathComponent("rollout-b.jsonl"), atomically: true, encoding: .utf8)
setenv("CODEX_SESSIONS_DIR", codexDir.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path, 1)

let codex = CodexUsageReader.read()
check(codex?.planType == "plus", "codex newest snapshot (5-hour file) wins over older monthly")
check(codex?.windows.count == 2, "codex primary + secondary both parsed")
check(codex?.windows.first?.label == "5-hour", "codex 299-minute window labelled 5-hour")
check(codex?.windows.first?.usedPercent == 12, "codex primary percentage parsed")
check(codex?.windows.last?.label == "Weekly", "codex 10080-minute window labelled Weekly")
if let fiveHourWindow = codex?.windows.first {
    // resets_in_seconds (3600) is relative to the 12:00:00Z event timestamp.
    let expected = ISO8601DateFormatter().date(from: "2026-07-20T12:00:00Z")!.addingTimeInterval(3600)
    check(abs(fiveHourWindow.resetsAt.timeIntervalSince(expected)) < 1,
          "codex relative reset resolved from event timestamp")
}
check(CodexWindow(usedPercent: 20, resetsAt: Date(), windowMinutes: 43800).label == "Monthly",
      "codex 43800-minute window labelled Monthly")
let firstScan = CodexUsageReader.scan()
check(firstScan?.usage == codex, "Codex scan returns the parsed usage")
let unchangedScan = firstScan.flatMap { CodexUsageReader.scan(changedFrom: $0.fingerprint) }
check(unchangedScan == nil, "unchanged Codex files skip parsing")
unsetenv("CODEX_SESSIONS_DIR")
try? FileManager.default.removeItem(at: codexDir.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())

print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) FAILED.")
exit(failures == 0 ? 0 : 1)
