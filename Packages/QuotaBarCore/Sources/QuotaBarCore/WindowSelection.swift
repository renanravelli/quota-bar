public enum SelectionReason: Sendable, Hashable {
    case originDidNotReport
    case originReportedUnknownValue(String)
    case originReportedWindowWithoutUtilization(QuotaWindow)
    case onlyOneWindowAvailable
}

public enum WindowSelection: Sendable, Hashable {
    case reportedByOrigin(QuotaWindow)
    case chosenByApp(QuotaWindow, reason: SelectionReason)

    public var window: QuotaWindow {
        switch self {
        case let .reportedByOrigin(window): window
        case let .chosenByApp(window, _): window
        }
    }
}

public enum WindowSelector {
    public static func select(from snapshot: QuotaSnapshot) -> WindowSelection? {
        if case let .window(reported) = snapshot.bindingWindow,
           snapshot.reading(for: reported).utilization != nil {
            return .reportedByOrigin(reported)
        }

        let fiveHour = snapshot.fiveHour.utilization
        let sevenDay = snapshot.sevenDay.utilization

        switch (fiveHour, sevenDay) {
        case (nil, nil):
            return nil
        case (.some, nil):
            return .chosenByApp(.fiveHour, reason: fallbackReason(in: snapshot, whenBothAvailable: false))
        case (nil, .some):
            return .chosenByApp(.sevenDay, reason: fallbackReason(in: snapshot, whenBothAvailable: false))
        case let (.some(fiveHourValue), .some(sevenDayValue)):
            let window: QuotaWindow = sevenDayValue > fiveHourValue ? .sevenDay : .fiveHour
            return .chosenByApp(window, reason: fallbackReason(in: snapshot, whenBothAvailable: true))
        }
    }

    private static func fallbackReason(in snapshot: QuotaSnapshot, whenBothAvailable: Bool) -> SelectionReason {
        switch snapshot.bindingWindow {
        case let .window(reported):
            return .originReportedWindowWithoutUtilization(reported)
        case let .unrecognized(rawValue):
            return .originReportedUnknownValue(rawValue)
        case nil:
            return whenBothAvailable ? .originDidNotReport : .onlyOneWindowAvailable
        }
    }
}
