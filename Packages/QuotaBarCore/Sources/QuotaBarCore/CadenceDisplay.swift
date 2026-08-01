import Foundation

public enum CadenceReinforcement: Sendable, Hashable {
    case none
    case idle
    case failure
    case deferral

    public init(_ nature: Cadence.Nature) {
        self = switch nature {
        case .base: .none
        case .idle: .idle
        case .widenedByFailure: .failure
        case .deferredBySystem: .deferral
        }
    }
}

public struct CadenceDisplay: Sendable, Hashable {
    public let cadence: Cadence
    public let progress: Double

    public init(cadence: Cadence, progress: Double) {
        self.cadence = cadence
        self.progress = min(max(progress, 0), 1)
    }

    public var nature: Cadence.Nature {
        cadence.nature
    }

    public var reinforcement: CadenceReinforcement {
        CadenceReinforcement(nature)
    }
}

public enum CadenceDisplayPolicy {
    public static func display(for cadence: Cadence?, expectedReadingAt: Date?, now: Date) -> CadenceDisplay? {
        guard let cadence, let expectedReadingAt else { return nil }

        let remaining = expectedReadingAt.timeIntervalSince(now)
        let interval = TimeInterval(cadence.interval.components.seconds)

        return CadenceDisplay(cadence: cadence, progress: 1 - remaining / interval)
    }
}
