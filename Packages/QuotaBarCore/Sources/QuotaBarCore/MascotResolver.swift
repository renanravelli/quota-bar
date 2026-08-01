public enum MascotExpression: Sendable, Hashable {
    case normal
    case attention
    case critical
    case exhausted
    case noValue
}

public enum MascotResolver {
    public static func expression(for state: IndicatorState) -> MascotExpression {
        switch state {
        case .notConfigured, .loading, .failed:
            .noValue
        case let .ready(value), let .stale(value), let .exhausted(value):
            expression(for: value.band)
        }
    }

    private static func expression(for band: ConsumptionBand) -> MascotExpression {
        switch band {
        case .normal: .normal
        case .attention: .attention
        case .critical: .critical
        case .exhausted: .exhausted
        }
    }
}
