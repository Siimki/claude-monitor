import Foundation

/// Account-wide Claude subscription limits reported with the latest local response.
public struct Usage: Equatable, Sendable {
    public let sessionPercent: Int
    public let sessionResetAt: Date
    public let weekPercent: Int?
    public let weekResetAt: Date?
    public let observedAt: Date

    public init(sessionPercent: Int, sessionResetAt: Date, weekPercent: Int? = nil,
                weekResetAt: Date? = nil, observedAt: Date = Date()) {
        self.sessionPercent = sessionPercent
        self.sessionResetAt = sessionResetAt
        self.weekPercent = weekPercent
        self.weekResetAt = weekResetAt
        self.observedAt = observedAt
    }
}
