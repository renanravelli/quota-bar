public enum IndicatorTextFormatter {
    public static let maxLength = 9

    public static func text(for state: IndicatorState) -> String {
        switch state {
        case .notConfigured, .loading, .failed:
            ""
        case let .ready(value), let .exhausted(value):
            "\(label(for: value.selection.window)) \(value.utilization.displayablePercent)%"
        case let .stale(value):
            "\(label(for: value.selection.window)) ~\(value.utilization.displayablePercent)%"
        }
    }

    private static func label(for window: QuotaWindow) -> String {
        switch window {
        case .fiveHour: "5h"
        case .sevenDay: "7d"
        }
    }
}
