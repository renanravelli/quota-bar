import Foundation

public enum SeriesUnit: Sendable, Hashable {
    case tokens
    case percent
}

public enum ChartMark: Sendable, Hashable {
    case measured(BucketKey, Double)
    case absence(BucketKey)
}

public struct ChartSeries: Sendable, Hashable {
    public let unit: SeriesUnit
    public let model: ModelIdentity?
    public let marks: [ChartMark]

    public init(unit: SeriesUnit, model: ModelIdentity?, marks: [ChartMark]) {
        self.unit = unit
        self.model = model
        self.marks = marks
    }
}

public struct ProjectionTrail: Sendable, Hashable {
    public let anchoredAt: Date
    public let reaching: Date
    public let basis: ProjectionBasis

    public init?(of projection: Projection) {
        guard case let .projected(exhaustion) = projection else { return nil }

        anchoredAt = exhaustion.basis.lastSampleAt
        reaching = exhaustion.at
        basis = exhaustion.basis
    }
}

public struct ChartModel: Sendable, Hashable {
    public let window: SeriesWindow
    public let granularity: BucketSize
    public let tokenSeries: [ChartSeries]
    public let quotaSeries: ChartSeries?
    public let projection: ProjectionTrail?
    public let freshness: SeriesFreshness
    public let renderedAt: Date

    public init(
        window: SeriesWindow,
        granularity: BucketSize,
        tokenSeries: [ChartSeries],
        quotaSeries: ChartSeries?,
        projection: ProjectionTrail?,
        freshness: SeriesFreshness,
        renderedAt: Date
    ) {
        self.window = window
        self.granularity = granularity
        self.tokenSeries = tokenSeries
        self.quotaSeries = quotaSeries
        self.projection = projection
        self.freshness = freshness
        self.renderedAt = renderedAt
    }
}
