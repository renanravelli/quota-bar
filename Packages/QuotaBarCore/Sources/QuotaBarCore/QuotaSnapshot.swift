import Foundation

public enum QuotaWindow: Sendable, Hashable {
    case fiveHour
    case sevenDay
}

public enum WindowStatus: Sendable, Hashable {
    case allowed
    case allowedWarning
    case rejected
    case unknown(String)
}

public struct WindowReading: Sendable, Hashable {
    public let utilization: Utilization?
    public let resetsAt: Date?
    public let status: WindowStatus?

    public init(utilization: Utilization?, resetsAt: Date?, status: WindowStatus?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
        self.status = status
    }
}

public struct OverageInfo: Sendable, Hashable {
    public let status: String?
    public let disabledReason: String?

    public init(status: String?, disabledReason: String?) {
        self.status = status
        self.disabledReason = disabledReason
    }
}

public enum QuotaSource: Sendable, Hashable {
    case primaryProbe
    case contingencyStatusLine

    public var requiresCredential: Bool {
        switch self {
        case .primaryProbe: true
        case .contingencyStatusLine: false
        }
    }
}

public enum BindingWindow: Sendable, Hashable {
    case window(QuotaWindow)
    case unrecognized(String)
}

public struct QuotaSnapshot: Sendable, Hashable {
    public let fiveHour: WindowReading
    public let sevenDay: WindowReading
    public let overallStatus: WindowStatus?
    public let nextResetAt: Date?
    public let bindingWindow: BindingWindow?
    public let fallbackPercentage: Utilization?
    public let overage: OverageInfo
    public let readSequence: UInt64
    public let readAt: Date
    public let source: QuotaSource

    public init?(
        fiveHour: WindowReading,
        sevenDay: WindowReading,
        overallStatus: WindowStatus?,
        nextResetAt: Date?,
        bindingWindow: BindingWindow?,
        fallbackPercentage: Utilization?,
        overage: OverageInfo,
        readSequence: UInt64,
        readAt: Date,
        source: QuotaSource
    ) {
        guard fiveHour.utilization != nil || sevenDay.utilization != nil else { return nil }

        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.overallStatus = overallStatus
        self.nextResetAt = nextResetAt
        self.bindingWindow = bindingWindow
        self.fallbackPercentage = fallbackPercentage
        self.overage = overage
        self.readSequence = readSequence
        self.readAt = readAt
        self.source = source
    }

    public func reading(for window: QuotaWindow) -> WindowReading {
        switch window {
        case .fiveHour: fiveHour
        case .sevenDay: sevenDay
        }
    }
}
