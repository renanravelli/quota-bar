import Foundation

public enum UnifiedRateLimitHeaders {
    public static func snapshot(
        from headers: [String: String],
        readSequence: UInt64,
        readAt: Date
    ) -> QuotaSnapshot? {
        let fields = fields(from: headers)

        return QuotaSnapshot(
            fiveHour: reading(.fiveHour, in: fields),
            sevenDay: reading(.sevenDay, in: fields),
            overallStatus: fields[Key.overallStatus].map(status),
            nextResetAt: fields[Key.nextReset].flatMap(instant),
            bindingWindow: fields[Key.representativeClaim].map(bindingWindow),
            fallbackPercentage: fields[Key.fallbackPercentage].flatMap(fraction),
            overage: OverageInfo(
                status: fields[Key.overageStatus],
                disabledReason: fields[Key.overageDisabledReason]
            ),
            readSequence: readSequence,
            readAt: readAt,
            source: .primaryProbe
        )
    }

    private enum Key {
        static let overallStatus = "anthropic-ratelimit-unified-status"
        static let nextReset = "anthropic-ratelimit-unified-reset"
        static let representativeClaim = "anthropic-ratelimit-unified-representative-claim"
        static let fallbackPercentage = "anthropic-ratelimit-unified-fallback-percentage"
        static let overageStatus = "anthropic-ratelimit-unified-overage-status"
        static let overageDisabledReason = "anthropic-ratelimit-unified-overage-disabled-reason"
    }

    private struct WindowKeys {
        let utilization: String
        let reset: String
        let status: String

        static let fiveHour = WindowKeys(
            utilization: "anthropic-ratelimit-unified-5h-utilization",
            reset: "anthropic-ratelimit-unified-5h-reset",
            status: "anthropic-ratelimit-unified-5h-status"
        )

        static let sevenDay = WindowKeys(
            utilization: "anthropic-ratelimit-unified-7d-utilization",
            reset: "anthropic-ratelimit-unified-7d-reset",
            status: "anthropic-ratelimit-unified-7d-status"
        )

        static func of(_ window: QuotaWindow) -> WindowKeys {
            switch window {
            case .fiveHour: fiveHour
            case .sevenDay: sevenDay
            }
        }
    }

    private static func fields(from headers: [String: String]) -> [String: String] {
        var fields = [String: String](minimumCapacity: headers.count)
        for (name, value) in headers {
            let text = value.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            fields[name.lowercased()] = text
        }
        return fields
    }

    private static func reading(_ window: QuotaWindow, in fields: [String: String]) -> WindowReading {
        let keys = WindowKeys.of(window)
        return WindowReading(
            utilization: fields[keys.utilization].flatMap(fraction),
            resetsAt: fields[keys.reset].flatMap(instant),
            status: fields[keys.status].map(status)
        )
    }

    private static func fraction(_ raw: String) -> Utilization? {
        guard isUnsignedDecimal(raw) else { return nil }
        return Utilization(originFraction: raw)
    }

    private static func instant(_ raw: String) -> Date? {
        guard isUnsignedInteger(raw), let epochSeconds = Int64(raw), epochSeconds > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(epochSeconds))
    }

    private static func status(_ raw: String) -> WindowStatus {
        switch raw {
        case "allowed": .allowed
        case "allowed_warning": .allowedWarning
        case "rejected": .rejected
        default: .unknown(raw)
        }
    }

    private static func bindingWindow(_ raw: String) -> BindingWindow {
        switch raw {
        case "five_hour": .window(.fiveHour)
        case "seven_day": .window(.sevenDay)
        default: .unrecognized(raw)
        }
    }

    private static func isUnsignedDecimal(_ text: String) -> Bool {
        var digits = 0
        var separators = 0

        for character in text {
            if character.isASCII, character.isNumber {
                digits += 1
            } else if character == "." {
                separators += 1
            } else {
                return false
            }
        }

        return digits > 0 && separators <= 1
    }

    private static func isUnsignedInteger(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber }
    }
}
