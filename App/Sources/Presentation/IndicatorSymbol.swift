import QuotaBarCore

enum IndicatorSymbol {
    static func name(for state: IndicatorState, source: QuotaSource) -> String {
        switch state {
        case .notConfigured: "key.slash"
        case .loading: "ellipsis.circle"
        case .failed: "exclamationmark.triangle.fill"
        case let .ready(value), let .exhausted(value), let .stale(value):
            name(for: value.band, source: source)
        }
    }

    static func name(for band: ConsumptionBand, source: QuotaSource) -> String {
        switch source {
        case .primaryProbe:
            switch band {
            case .normal: "gauge.with.dots.needle.bottom.0percent"
            case .attention: "gauge.with.dots.needle.bottom.50percent"
            case .critical: "gauge.with.dots.needle.bottom.100percent"
            case .exhausted: "exclamationmark.octagon.fill"
            }
        case .contingencyStatusLine:
            switch band {
            case .normal: "circle.dashed"
            case .attention: "circle.dashed.inset.filled"
            case .critical: "exclamationmark.circle"
            case .exhausted: "xmark.octagon"
            }
        }
    }
}
