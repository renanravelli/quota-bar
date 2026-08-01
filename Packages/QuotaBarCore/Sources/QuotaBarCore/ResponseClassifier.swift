import Foundation

public enum ResponseClassifier {
    public static func classify(
        status: Int,
        headers: [String: String],
        errorBody: Data?,
        readSequence: UInt64,
        readAt: Date
    ) -> ProbeResult {
        switch status {
        case HTTPStatus.success:
            reading(from: headers, readSequence: readSequence, readAt: readAt) ?? .failed(.unexpectedResponse)
        case HTTPStatus.tooManyRequests:
            reading(from: headers, readSequence: readSequence, readAt: readAt)
                ?? .throttled(retryAfter: retryAfter(in: headers))
        case HTTPStatus.unauthorized, HTTPStatus.forbidden:
            .failed(credentialFailure(evidenceIn: errorBody))
        case HTTPStatus.serverError:
            .throttled(retryAfter: retryAfter(in: headers))
        default:
            .failed(.unexpectedResponse)
        }
    }

    private static func reading(
        from headers: [String: String],
        readSequence: UInt64,
        readAt: Date
    ) -> ProbeResult? {
        UnifiedRateLimitHeaders
            .snapshot(from: headers, readSequence: readSequence, readAt: readAt)
            .map(ProbeResult.reading)
    }

    private static func retryAfter(in headers: [String: String]) -> Duration? {
        let value = headers.first { $0.key.caseInsensitiveCompare(retryAfterHeader) == .orderedSame }?.value

        guard let seconds = value.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }), seconds >= 0 else {
            return nil
        }
        return .seconds(seconds)
    }

    private static func credentialFailure(evidenceIn errorBody: Data?) -> FailureReason {
        guard let message = errorMessage(in: errorBody)?.lowercased() else { return .credentialRejected }

        if policyEvidence.contains(where: { message.contains($0) }) { return .blockedByPolicy }
        if expirationEvidence.contains(where: { message.contains($0) }) { return .credentialExpired }
        return .credentialRejected
    }

    private static func errorMessage(in errorBody: Data?) -> String? {
        guard let errorBody, !errorBody.isEmpty else { return nil }
        return (try? JSONDecoder().decode(ErrorEnvelope.self, from: errorBody))?.error.message
    }

    private static let retryAfterHeader = "retry-after"
    private static let policyEvidence = ["authorized for use with claude code"]
    private static let expirationEvidence = ["expired"]

    private struct ErrorEnvelope: Decodable {
        struct Failure: Decodable {
            let message: String
        }

        let error: Failure
    }

    private enum HTTPStatus {
        static let success = 200...299
        static let unauthorized = 401
        static let forbidden = 403
        static let tooManyRequests = 429
        static let serverError = 500...599
    }
}
