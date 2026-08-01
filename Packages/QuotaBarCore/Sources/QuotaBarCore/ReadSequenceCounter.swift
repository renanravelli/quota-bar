import Foundation

public struct ReadSequenceCounter: Sendable, Hashable {
    public private(set) var candidate: UInt64

    public init(startingAt candidate: UInt64 = 1) {
        self.candidate = candidate
    }

    public mutating func classify(
        status: Int,
        headers: [String: String],
        errorBody: Data?,
        readAt: Date
    ) -> ProbeResult {
        let result = ResponseClassifier.classify(
            status: status,
            headers: headers,
            errorBody: errorBody,
            readSequence: candidate,
            readAt: readAt
        )

        if case .reading = result { candidate &+= 1 }
        return result
    }
}
