import Foundation

public struct UnifiedRateLimitHeaderFixture: Sendable {
    public static let fiveHourResetsAt = Date(timeIntervalSince1970: 1_700_003_600)
    public static let sevenDayResetsAt = Date(timeIntervalSince1970: 1_700_086_400)

    public var fiveHourUtilization: String?
    public var fiveHourReset: String?
    public var fiveHourStatus: String?
    public var sevenDayUtilization: String?
    public var sevenDayReset: String?
    public var sevenDayStatus: String?
    public var overallStatus: String?
    public var nextReset: String?
    public var representativeClaim: String?
    public var fallbackPercentage: String?
    public var overageStatus: String?
    public var overageDisabledReason: String?

    public init(
        fiveHourUtilization: String? = nil,
        fiveHourReset: String? = nil,
        fiveHourStatus: String? = nil,
        sevenDayUtilization: String? = nil,
        sevenDayReset: String? = nil,
        sevenDayStatus: String? = nil,
        overallStatus: String? = nil,
        nextReset: String? = nil,
        representativeClaim: String? = nil,
        fallbackPercentage: String? = nil,
        overageStatus: String? = nil,
        overageDisabledReason: String? = nil
    ) {
        self.fiveHourUtilization = fiveHourUtilization
        self.fiveHourReset = fiveHourReset
        self.fiveHourStatus = fiveHourStatus
        self.sevenDayUtilization = sevenDayUtilization
        self.sevenDayReset = sevenDayReset
        self.sevenDayStatus = sevenDayStatus
        self.overallStatus = overallStatus
        self.nextReset = nextReset
        self.representativeClaim = representativeClaim
        self.fallbackPercentage = fallbackPercentage
        self.overageStatus = overageStatus
        self.overageDisabledReason = overageDisabledReason
    }

    public static let complete = UnifiedRateLimitHeaderFixture(
        fiveHourUtilization: "0.789",
        fiveHourReset: "1700003600",
        fiveHourStatus: "allowed_warning",
        sevenDayUtilization: "0.1875",
        sevenDayReset: "1700086400",
        sevenDayStatus: "allowed",
        overallStatus: "allowed_warning",
        nextReset: "1700003600",
        representativeClaim: "five_hour",
        fallbackPercentage: "0.42",
        overageStatus: "disabled",
        overageDisabledReason: "not_enrolled"
    )

    public static let exhausted = UnifiedRateLimitHeaderFixture(
        fiveHourUtilization: "1.0",
        fiveHourReset: "1700003600",
        fiveHourStatus: "rejected",
        sevenDayUtilization: "0.62",
        sevenDayReset: "1700086400",
        sevenDayStatus: "allowed",
        overallStatus: "rejected",
        nextReset: "1700003600",
        representativeClaim: "five_hour"
    )

    public var headers: [String: String] {
        var headers: [String: String] = [:]
        headers["anthropic-ratelimit-unified-5h-utilization"] = fiveHourUtilization
        headers["anthropic-ratelimit-unified-5h-reset"] = fiveHourReset
        headers["anthropic-ratelimit-unified-5h-status"] = fiveHourStatus
        headers["anthropic-ratelimit-unified-7d-utilization"] = sevenDayUtilization
        headers["anthropic-ratelimit-unified-7d-reset"] = sevenDayReset
        headers["anthropic-ratelimit-unified-7d-status"] = sevenDayStatus
        headers["anthropic-ratelimit-unified-status"] = overallStatus
        headers["anthropic-ratelimit-unified-reset"] = nextReset
        headers["anthropic-ratelimit-unified-representative-claim"] = representativeClaim
        headers["anthropic-ratelimit-unified-fallback-percentage"] = fallbackPercentage
        headers["anthropic-ratelimit-unified-overage-status"] = overageStatus
        headers["anthropic-ratelimit-unified-overage-disabled-reason"] = overageDisabledReason
        return headers
    }
}
