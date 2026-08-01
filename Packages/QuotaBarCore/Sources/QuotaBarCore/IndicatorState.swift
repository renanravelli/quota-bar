public enum ConsumptionBand: Sendable, Hashable {
    case normal
    case attention
    case critical
    case exhausted

    init(utilization: Utilization) {
        if utilization.isAtOrAboveLimit {
            self = .exhausted
            return
        }

        switch utilization.truncatedPercent {
        case ..<75: self = .normal
        case ..<90: self = .attention
        default: self = .critical
        }
    }
}

public struct DisplayValue: Sendable, Hashable {
    public let selection: WindowSelection
    public let utilization: Utilization
    public let band: ConsumptionBand

    public init(selection: WindowSelection, utilization: Utilization, band: ConsumptionBand) {
        self.selection = selection
        self.utilization = utilization
        self.band = band
    }
}

public enum IndicatorState: Sendable, Hashable {
    case notConfigured
    case loading
    case failed(FailureReason)
    case stale(DisplayValue)
    case exhausted(DisplayValue)
    case ready(DisplayValue)
}
