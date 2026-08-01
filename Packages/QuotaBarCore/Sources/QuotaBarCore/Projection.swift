import Foundation

public enum UnavailabilityReason: Sendable, Hashable {
    case seriesBeginsAtFirstReading
    case noUtilizationForWindow
    case persistedSeriesWasUnreadable
}

public enum InsufficiencyReason: Sendable, Hashable {
    case quantity(observed: Int, required: Int)
    case span(observed: Duration, required: Duration)
    case continuity(largestGap: Duration, tolerated: Duration)
}

public struct ProjectionBasis: Sendable, Hashable {
    public let sampleCount: Int
    public let firstSampleAt: Date
    public let lastSampleAt: Date
    public let coveredFractionOfElapsedWindow: Double
    public let resetInstantKnown: Bool

    public init(
        sampleCount: Int,
        firstSampleAt: Date,
        lastSampleAt: Date,
        coveredFractionOfElapsedWindow: Double,
        resetInstantKnown: Bool
    ) {
        self.sampleCount = sampleCount
        self.firstSampleAt = firstSampleAt
        self.lastSampleAt = lastSampleAt
        self.coveredFractionOfElapsedWindow = coveredFractionOfElapsedWindow
        self.resetInstantKnown = resetInstantKnown
    }

    public func ageOfLastSample(at now: Date) -> Duration {
        .seconds(max(0, now.timeIntervalSince(lastSampleAt)))
    }
}

public struct ProjectedExhaustion: Sendable, Hashable {
    public let ratePerHour: Double
    public let at: Date
    public let basis: ProjectionBasis

    public init(ratePerHour: Double, at: Date, basis: ProjectionBasis) {
        self.ratePerHour = ratePerHour
        self.at = at
        self.basis = basis
    }
}

public enum Projection: Sendable, Hashable {
    case unavailable(UnavailabilityReason)
    case exhausted(resetsAt: Date?)
    case insufficientSample(InsufficiencyReason)
    case noObservedConsumption(ratePerHour: Double, basis: ProjectionBasis)
    case resetsBeforeExhausting(resetsAt: Date, ratePerHour: Double, basis: ProjectionBasis)
    case projected(ProjectedExhaustion)

    public var basis: ProjectionBasis? {
        switch self {
        case .unavailable, .exhausted, .insufficientSample: nil
        case let .noObservedConsumption(_, basis): basis
        case let .resetsBeforeExhausting(_, _, basis): basis
        case let .projected(exhaustion): exhaustion.basis
        }
    }

    public var ratePerHour: Double? {
        switch self {
        case .unavailable, .exhausted, .insufficientSample: nil
        case let .noObservedConsumption(rate, _): rate
        case let .resetsBeforeExhausting(_, rate, _): rate
        case let .projected(exhaustion): exhaustion.ratePerHour
        }
    }
}
