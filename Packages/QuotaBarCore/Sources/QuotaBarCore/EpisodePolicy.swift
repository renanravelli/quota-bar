public enum EpisodeTrigger: Sendable, Hashable {
    case stateChanged
    case bandCrossed
    case displayedWindowChanged
    case sourceModeChanged
}

public enum EpisodePolicy {
    public static let maxDuration: Duration = .milliseconds(600)

    public static func trigger(
        from previous: IndicatorState,
        to current: IndicatorState,
        previousSource: QuotaSource?,
        currentSource: QuotaSource?
    ) -> EpisodeTrigger? {
        if identity(of: previous) != identity(of: current) {
            return .stateChanged
        }
        if band(of: previous) != band(of: current) {
            return .bandCrossed
        }
        if window(of: previous) != window(of: current) {
            return .displayedWindowChanged
        }
        if previousSource != currentSource {
            return .sourceModeChanged
        }
        return nil
    }

    private enum StateIdentity: Hashable {
        case notConfigured
        case loading
        case failed(FailureReason)
        case ready
        case stale
        case exhausted
    }

    private static func identity(of state: IndicatorState) -> StateIdentity {
        switch state {
        case .notConfigured: .notConfigured
        case .loading: .loading
        case let .failed(reason): .failed(reason)
        case .ready: .ready
        case .stale: .stale
        case .exhausted: .exhausted
        }
    }

    private static func band(of state: IndicatorState) -> ConsumptionBand? {
        displayValue(of: state)?.band
    }

    private static func window(of state: IndicatorState) -> QuotaWindow? {
        displayValue(of: state)?.selection.window
    }

    private static func displayValue(of state: IndicatorState) -> DisplayValue? {
        switch state {
        case let .ready(value), let .stale(value), let .exhausted(value): value
        case .notConfigured, .loading, .failed: nil
        }
    }
}
