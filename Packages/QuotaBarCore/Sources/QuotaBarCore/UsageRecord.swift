import Foundation

public struct UsageKey: Sendable, Hashable {
    public enum Origin: Sendable, Hashable, CaseIterable {
        case messageID
        case requestID
        case uuid
    }

    public let value: String
    public let origin: Origin

    public init(value: String, origin: Origin) {
        self.value = value
        self.origin = origin
    }

    public init?(messageID: String?, requestID: String?, uuid: String?) {
        if let messageID, !messageID.isEmpty {
            self.init(value: messageID, origin: .messageID)
        } else if let requestID, !requestID.isEmpty {
            self.init(value: requestID, origin: .requestID)
        } else if let uuid, !uuid.isEmpty {
            self.init(value: uuid, origin: .uuid)
        } else {
            return nil
        }
    }
}

public struct ModelContribution: Sendable, Hashable {
    public let model: ModelIdentity
    public let counts: TokenCounts

    public init(model: ModelIdentity, counts: TokenCounts) {
        self.model = model
        self.counts = counts
    }
}

public struct UsageRecord: Sendable, Hashable {
    public let key: UsageKey
    public let occurredAt: Date
    public let contributions: [ModelContribution]

    public init(key: UsageKey, occurredAt: Date, contributions: [ModelContribution]) {
        self.key = key
        self.occurredAt = occurredAt
        self.contributions = contributions
    }

    public var counts: TokenCounts {
        contributions.reduce(.zero) { $0 + $1.counts }
    }
}

public struct ScanPosition: Sendable, Hashable, Comparable {
    public let fileOrdinal: Int
    public let lineOrdinal: Int

    public init(fileOrdinal: Int, lineOrdinal: Int) {
        self.fileOrdinal = fileOrdinal
        self.lineOrdinal = lineOrdinal
    }

    public static func < (lhs: ScanPosition, rhs: ScanPosition) -> Bool {
        (lhs.fileOrdinal, lhs.lineOrdinal) < (rhs.fileOrdinal, rhs.lineOrdinal)
    }
}
