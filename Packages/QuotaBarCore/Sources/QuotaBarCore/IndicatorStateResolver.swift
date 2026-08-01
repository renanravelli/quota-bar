import Foundation

public enum IndicatorStateResolver {
    public static func resolve(
        state: QuotaState,
        latch: inout StaleLatch,
        now: Date
    ) -> IndicatorState {
        let displayValue = displayValue(in: state)

        if !state.credentialPresent, !hasValueFromCredentialFreeSource(state, displayValue) {
            return .notConfigured
        }

        guard let displayValue, let snapshot = state.snapshot else {
            switch state.lastAttempt {
            case let .failed(reason): return .failed(reason)
            case .inProgress: return .loading
            case .succeeded: return .failed(.unexpectedResponse)
            }
        }

        let wentStale = latch.evaluate(
            readSequence: snapshot.readSequence,
            readingAt: snapshot.readAt,
            now: now,
            maxIdleCadenceSinceReading: state.maxIdleCadenceSinceReading,
            displayedWindowResetPassed: resetPassed(for: displayValue.selection.window, in: snapshot, at: now)
        )

        if wentStale {
            return .stale(displayValue)
        }
        if displayValue.utilization.isAtOrAboveLimit {
            return .exhausted(displayValue)
        }
        return .ready(displayValue)
    }

    private static func displayValue(in state: QuotaState) -> DisplayValue? {
        guard let snapshot = state.snapshot,
              let selection = WindowSelector.select(from: snapshot),
              let utilization = snapshot.reading(for: selection.window).utilization
        else { return nil }

        return DisplayValue(
            selection: selection,
            utilization: utilization,
            band: ConsumptionBand(utilization: utilization)
        )
    }

    private static func hasValueFromCredentialFreeSource(
        _ state: QuotaState,
        _ displayValue: DisplayValue?
    ) -> Bool {
        guard displayValue != nil, let snapshot = state.snapshot else { return false }
        return !snapshot.source.requiresCredential
    }

    private static func resetPassed(
        for window: QuotaWindow,
        in snapshot: QuotaSnapshot,
        at now: Date
    ) -> Bool {
        guard let resetsAt = snapshot.reading(for: window).resetsAt else { return false }
        return now > resetsAt
    }
}
