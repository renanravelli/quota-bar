public enum WorkBand: Sendable, Hashable {
    case absent
    case light
    case steady
    case intense

    public static func of(_ model: TokenCounts, inTotal: TokenCounts) -> WorkBand {
        let worked = model.total.value
        let whole = inTotal.total.value
        guard worked > 0, whole > 0 else { return .absent }

        let workedInTenths = worked * tenths
        if workedInTenths <= whole * lightCeilingInTenths { return .light }
        if workedInTenths <= whole * steadyCeilingInTenths { return .steady }
        return .intense
    }

    private static let tenths = 10
    private static let lightCeilingInTenths = 1
    private static let steadyCeilingInTenths = 5
}
