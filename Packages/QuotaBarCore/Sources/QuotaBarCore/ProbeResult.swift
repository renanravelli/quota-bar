import Foundation

public enum ProbeResult: Sendable, Equatable {
    case reading(QuotaSnapshot)
    case throttled(retryAfter: Duration?)
    case failed(FailureReason)
}
