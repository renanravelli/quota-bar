import Foundation

public struct RawUsage: Sendable, Hashable {
    public let input: Int?
    public let output: Int?
    public let cacheRead: Int?
    public let cacheCreation: Int?
    public let malformedCounters: [String]

    public init(
        input: Int?,
        output: Int?,
        cacheRead: Int?,
        cacheCreation: Int?,
        malformedCounters: [String] = []
    ) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheCreation = cacheCreation
        self.malformedCounters = malformedCounters
    }
}

public struct RawIteration: Sendable, Hashable {
    public let model: String?
    public let usage: RawUsage

    public init(model: String?, usage: RawUsage) {
        self.model = model
        self.usage = usage
    }
}

public enum UnusableReason: Error, Sendable, Hashable {
    case missingKey
    case missingTimestamp
    case missingModel
    case missingCounters
    case malformedCounter(String)
    case negativeCounter
    case futureTimestamp
    case undecodableLine
}

public enum UsageRecordFactory {
    public static func make(
        key: UsageKey?,
        occurredAt: Date?,
        model: String?,
        topLevel: RawUsage?,
        iterations: [RawIteration]
    ) -> Result<UsageRecord, UnusableReason> {
        guard let key else { return .failure(.missingKey) }
        guard let occurredAt else { return .failure(.missingTimestamp) }

        let parcels: [RawIteration] = iterations.isEmpty
            ? [RawIteration(model: model, usage: topLevel ?? .absent)]
            : iterations

        var contributions: [ModelContribution] = []
        contributions.reserveCapacity(parcels.count)

        for parcel in parcels {
            guard let identifier = parcel.model ?? model else { return .failure(.missingModel) }

            switch counts(of: parcel.usage) {
            case .success(let counts):
                contributions.append(ModelContribution(model: ModelIdentity(recorded: identifier), counts: counts))
            case .failure(let reason):
                return .failure(reason)
            }
        }

        return .success(UsageRecord(key: key, occurredAt: occurredAt, contributions: contributions))
    }

    private static func counts(of usage: RawUsage) -> Result<TokenCounts, UnusableReason> {
        if let malformed = usage.malformedCounters.first { return .failure(.malformedCounter(malformed)) }

        let declared = [usage.input, usage.output, usage.cacheRead, usage.cacheCreation]
        guard declared.contains(where: { $0 != nil }) else { return .failure(.missingCounters) }
        guard declared.allSatisfy({ ($0 ?? 0) >= 0 }) else { return .failure(.negativeCounter) }

        return .success(
            TokenCounts(
                input: usage.input ?? 0,
                output: usage.output ?? 0,
                cacheRead: usage.cacheRead ?? 0,
                cacheCreation: usage.cacheCreation ?? 0
            )
        )
    }
}

private extension RawUsage {
    static let absent = RawUsage(input: nil, output: nil, cacheRead: nil, cacheCreation: nil)
}
