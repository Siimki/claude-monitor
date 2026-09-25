import Foundation

/// A single Codex rate-limit window (e.g. the monthly limit today; a 5-hour or
/// weekly window if OpenAI adds one later). The window's duration is carried
/// verbatim so new window types render without code changes.
public struct CodexWindow: Equatable, Sendable {
    public let usedPercent: Int
    public let resetsAt: Date
    public let windowMinutes: Int

    public init(usedPercent: Int, resetsAt: Date, windowMinutes: Int) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.windowMinutes = windowMinutes
    }

    /// Human label derived from the window length. Buckets cover the windows
    /// OpenAI plausibly uses (5-hour ≈ 300m, daily ≈ 1440m, weekly ≈ 10080m,
    /// monthly ≈ 43800m); anything else falls through to "Monthly".
    public var label: String {
        switch windowMinutes {
        case ..<600:          return "5-hour"
        case 600..<2880:      return "Daily"
        case 2880..<20160:    return "Weekly"
        default:              return "Monthly"
        }
    }
}

/// The freshest account-wide Codex usage snapshot read from the CLI's rollout logs.
public struct CodexUsage: Equatable, Sendable {
    /// Windows ordered shortest-first, so the most immediate limit reads first.
    public let windows: [CodexWindow]
    public let planType: String?
    public let observedAt: Date

    public init(windows: [CodexWindow], planType: String? = nil, observedAt: Date) {
        self.windows = windows.sorted { $0.windowMinutes < $1.windowMinutes }
        self.planType = planType
        self.observedAt = observedAt
    }
}
