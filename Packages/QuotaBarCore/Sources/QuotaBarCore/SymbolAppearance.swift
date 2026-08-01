public enum SymbolShape: Sendable, Hashable {
    case normal
    case attention
    case critical
    case exhausted
}

public enum SymbolFill: Sendable, Hashable {
    case standard
    case contingency
}

public enum SymbolTint: Sendable, Hashable {
    case template
    case colored(RGBColor)
}

public struct SymbolAppearance: Sendable, Hashable {
    public let shape: SymbolShape?
    public let fill: SymbolFill
    public let tint: SymbolTint

    public init(shape: SymbolShape?, fill: SymbolFill, tint: SymbolTint) {
        self.shape = shape
        self.fill = fill
        self.tint = tint
    }
}

public enum SymbolResolver {
    public static func appearance(
        for state: IndicatorState,
        source: QuotaSource?,
        inEpisode: Bool
    ) -> SymbolAppearance {
        SymbolAppearance(
            shape: shape(for: state),
            fill: fill(for: source),
            tint: tint(for: state, inEpisode: inEpisode)
        )
    }

    private static func shape(for state: IndicatorState) -> SymbolShape? {
        switch state {
        case .notConfigured, .loading, .failed:
            nil
        case let .ready(value), let .stale(value), let .exhausted(value):
            shape(for: value.band)
        }
    }

    private static func shape(for band: ConsumptionBand) -> SymbolShape {
        switch band {
        case .normal: .normal
        case .attention: .attention
        case .critical: .critical
        case .exhausted: .exhausted
        }
    }

    private static func fill(for source: QuotaSource?) -> SymbolFill {
        source == .contingencyStatusLine ? .contingency : .standard
    }

    private static func tint(for state: IndicatorState, inEpisode: Bool) -> SymbolTint {
        if inEpisode {
            return .colored(episodeColor(for: state))
        }
        if case let .exhausted(value) = state {
            return .colored(ConsumptionGradient.color(for: value.utilization))
        }
        return .template
    }

    private static func episodeColor(for state: IndicatorState) -> RGBColor {
        switch state {
        case let .ready(value), let .stale(value), let .exhausted(value):
            ConsumptionGradient.color(for: value.utilization)
        case .notConfigured, .loading, .failed:
            Palette.accent
        }
    }
}
