import Foundation

public struct IngestionHealth: Sendable, Hashable {
    public let scanned: Int
    public let usable: Int
    public let unrecognized: Int
    public let recentScanned: Int
    public let recentUnrecognized: Int
    public let monotonicityViolations: Int
    public let observedProducerVersions: Set<String>

    public init(
        scanned: Int = 0,
        usable: Int = 0,
        unrecognized: Int = 0,
        recentScanned: Int = 0,
        recentUnrecognized: Int = 0,
        monotonicityViolations: Int = 0,
        observedProducerVersions: Set<String> = []
    ) {
        self.scanned = scanned
        self.usable = usable
        self.unrecognized = unrecognized
        self.recentScanned = recentScanned
        self.recentUnrecognized = recentUnrecognized
        self.monotonicityViolations = monotonicityViolations
        self.observedProducerVersions = observedProducerVersions
    }
}

public struct BreakReason: Sendable, Hashable {
    public let unrecognizedFraction: Double
    public let toleratedFraction: Double
    public let recentScanned: Int
    public let observedProducerVersions: Set<String>

    public init(
        unrecognizedFraction: Double,
        toleratedFraction: Double,
        recentScanned: Int,
        observedProducerVersions: Set<String>
    ) {
        self.unrecognizedFraction = unrecognizedFraction
        self.toleratedFraction = toleratedFraction
        self.recentScanned = recentScanned
        self.observedProducerVersions = observedProducerVersions
    }
}

public enum UsageAbsence: Sendable, Hashable {
    case directoryMissing
    case noReadableFile
    case noUsageEvent
    case noEventInSelectedPeriod(availableFrom: Date, availableTo: Date)
}

public enum IngestionVerdict: Sendable, Hashable {
    case healthy
    case broken(BreakReason)
    case absent(UsageAbsence)
}

public enum IngestionHealthPolicy {
    public static let recentWindow: Duration = .seconds(7 * 24 * 3_600)
    public static let minimumRecentSample = 20
    public static let maximumUnrecognizedFraction = 0.05

    public static func verdict(for health: IngestionHealth) -> IngestionVerdict {
        guard health.recentScanned >= minimumRecentSample else { return .healthy }

        let fraction = Double(health.recentUnrecognized) / Double(health.recentScanned)
        guard fraction > maximumUnrecognizedFraction else { return .healthy }

        return .broken(
            BreakReason(
                unrecognizedFraction: fraction,
                toleratedFraction: maximumUnrecognizedFraction,
                recentScanned: health.recentScanned,
                observedProducerVersions: health.observedProducerVersions
            )
        )
    }
}
