import Foundation

public struct Utilization: Sendable, Hashable, Comparable {
    private static let basisPointsPerPercent = 100
    private static let basisPointsPerUnitFraction = basisPointsPerPercent * 100
    private static let basisPointsAtLimit = basisPointsPerUnitFraction

    public let basisPoints: Int

    public init?(basisPoints: Int) {
        guard basisPoints >= 0 else { return nil }
        self.basisPoints = basisPoints
    }

    public init?(originFraction: String) {
        guard let fraction = Decimal(string: originFraction) else { return nil }
        self.init(scaling: fraction, by: Self.basisPointsPerUnitFraction)
    }

    public init?(originPercent: Decimal) {
        self.init(scaling: originPercent, by: Self.basisPointsPerPercent)
    }

    public var truncatedPercent: Int {
        basisPoints / Self.basisPointsPerPercent
    }

    public var isAtOrAboveLimit: Bool {
        basisPoints >= Self.basisPointsAtLimit
    }

    public static func < (lhs: Utilization, rhs: Utilization) -> Bool {
        lhs.basisPoints < rhs.basisPoints
    }

    private init?(scaling value: Decimal, by factor: Int) {
        guard !value.isNaN, value >= .zero else { return nil }

        var scaled = value * Decimal(factor)
        guard scaled <= Decimal(Int.max) else { return nil }

        var whole = Decimal()
        NSDecimalRound(&whole, &scaled, 0, .down)

        self.init(basisPoints: (whole as NSDecimalNumber).intValue)
    }
}
