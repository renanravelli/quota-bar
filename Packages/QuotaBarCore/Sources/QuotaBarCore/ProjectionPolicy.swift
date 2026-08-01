import Foundation

public enum ProjectionPolicy {
    public static let minimumSamples = 3
    public static let minimumSpanFractionOfWindow = 0.05
    public static let gapToleranceFactor = 2

    private static let limitInPercentagePoints = 100.0
    private static let secondsPerHour = 3_600.0

    public static func granularity(for window: QuotaWindow) -> Duration {
        switch window {
        case .fiveHour: .seconds(300)
        case .sevenDay: .seconds(3_600)
        }
    }

    public static func minimumSpan(for window: QuotaWindow) -> Duration {
        .seconds(nominalSeconds(of: window) * minimumSpanFractionOfWindow)
    }

    public static func gapTolerance(maxIdleCadence: Duration) -> Duration {
        maxIdleCadence * gapToleranceFactor
    }

    public static func project(
        _ series: QuotaSampleSeries,
        window: QuotaWindow,
        sinceResetAt: Date,
        maxIdleCadence: Duration,
        now: Date
    ) -> Projection {
        let usable = series.samples(of: window, sinceResetAt: sinceResetAt).filter { $0.readAt <= now }

        guard let last = usable.last, let first = usable.first,
              let latest = last.utilization(of: window), let earliest = first.utilization(of: window)
        else { return .unavailable(unavailability(of: series)) }

        let resetsAt = last.resetsAt(of: window)
        guard !latest.isAtOrAboveLimit else { return .exhausted(resetsAt: resetsAt) }

        guard usable.count >= minimumSamples else {
            return .insufficientSample(.quantity(observed: usable.count, required: minimumSamples))
        }

        let spanInSeconds = last.readAt.timeIntervalSince(first.readAt)
        let requiredSpan = minimumSpan(for: window)
        guard Duration.seconds(spanInSeconds) >= requiredSpan else {
            return .insufficientSample(.span(observed: .seconds(spanInSeconds), required: requiredSpan))
        }

        let tolerance = gapTolerance(maxIdleCadence: maxIdleCadence)
        let largestGap = largestInternalGap(of: usable)
        guard largestGap <= tolerance else {
            return .insufficientSample(.continuity(largestGap: largestGap, tolerated: tolerance))
        }

        let consumed = percentagePoints(of: latest) - percentagePoints(of: earliest)
        let ratePerHour = consumed * secondsPerHour / spanInSeconds
        let basis = ProjectionBasis(
            sampleCount: usable.count,
            firstSampleAt: first.readAt,
            lastSampleAt: last.readAt,
            coveredFractionOfElapsedWindow: coveredFraction(
                spanInSeconds: spanInSeconds,
                elapsedInSeconds: now.timeIntervalSince(sinceResetAt)
            ),
            resetInstantKnown: resetsAt != nil
        )

        guard ratePerHour > 0 else { return .noObservedConsumption(ratePerHour: ratePerHour, basis: basis) }

        let remaining = limitInPercentagePoints - percentagePoints(of: latest)
        let exhaustionAt = last.readAt.addingTimeInterval(remaining / ratePerHour * secondsPerHour)

        if let resetsAt, exhaustionAt > resetsAt {
            return .resetsBeforeExhausting(resetsAt: resetsAt, ratePerHour: ratePerHour, basis: basis)
        }

        return .projected(
            ProjectedExhaustion(
                ratePerHour: ratePerHour,
                at: rounded(exhaustionAt, to: granularity(for: window)),
                basis: basis
            )
        )
    }

    private static func unavailability(of series: QuotaSampleSeries) -> UnavailabilityReason {
        guard !series.coverage.isEmpty else {
            return series.restoration == .restartedAfterUnreadableLog
                ? .persistedSeriesWasUnreadable
                : .seriesBeginsAtFirstReading
        }
        return .noUtilizationForWindow
    }

    private static func largestInternalGap(of samples: [QuotaSample]) -> Duration {
        let widest = zip(samples, samples.dropFirst())
            .map { $1.readAt.timeIntervalSince($0.readAt) }
            .max() ?? 0

        return .seconds(widest)
    }

    private static func coveredFraction(spanInSeconds: Double, elapsedInSeconds: Double) -> Double {
        guard elapsedInSeconds > 0 else { return 0 }
        return min(1, spanInSeconds / elapsedInSeconds)
    }

    private static func percentagePoints(of utilization: Utilization) -> Double {
        Double(utilization.basisPoints) / 100
    }

    private static func rounded(_ instant: Date, to granularity: Duration) -> Date {
        let step = seconds(of: granularity)
        let elapsed = instant.timeIntervalSinceReferenceDate

        return Date(timeIntervalSinceReferenceDate: (elapsed / step).rounded() * step)
    }

    private static func seconds(of duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    private static func nominalSeconds(of window: QuotaWindow) -> Double {
        switch window {
        case .fiveHour: 5 * secondsPerHour
        case .sevenDay: 7 * 24 * secondsPerHour
        }
    }
}
