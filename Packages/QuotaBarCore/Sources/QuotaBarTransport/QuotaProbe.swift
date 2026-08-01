import Foundation
import QuotaBarCore

public enum ProbeOutcome: Sendable, Equatable {
    case probed(ProbeResult)
    case credentialUnavailable(KeychainFailure)
}

public actor QuotaProbe {
    private let transport: any ProbeTransporting
    private let credentials: any CredentialStoring
    private let models: [String]

    private var model: Int
    private var sequence: ReadSequenceCounter

    public init(
        transport: any ProbeTransporting,
        credentials: any CredentialStoring,
        models: [String] = ProbeModel.ordered
    ) {
        self.transport = transport
        self.credentials = credentials
        self.models = models.isEmpty ? ProbeModel.ordered : models
        model = 0
        sequence = ReadSequenceCounter()
    }

    public func continueReadSequence(after restored: UInt64) {
        sequence = ReadSequenceCounter(startingAt: restored &+ 1)
    }

    public func read(claudeCodeVersion: String, at readAt: Date) async -> ProbeOutcome {
        switch await credentials.load() {
        case .failure(let failure):
            return .credentialUnavailable(failure)
        case .success(let token):
            return .probed(await read(using: token, claudeCodeVersion: claudeCodeVersion, at: readAt))
        }
    }

    public func read(
        using token: SubscriptionToken,
        claudeCodeVersion: String,
        at readAt: Date
    ) async -> ProbeResult {
        for _ in models.indices {
            let request = ProbeRequestFactory.make(
                model: models[model],
                claudeCodeVersion: claudeCodeVersion,
                token: token
            )

            guard let response = try? await transport.send(request) else {
                return .failed(.communicationFailure)
            }

            guard ProbeModelAvailability.isModelUnavailable(status: response.status, body: response.body) else {
                return classify(response, at: readAt)
            }

            model = (model + 1) % models.count
        }

        return .failed(.unexpectedResponse)
    }

    private func classify(_ response: ProbeHTTPResponse, at readAt: Date) -> ProbeResult {
        let succeeded = ProbeModelAvailability.successStatus.contains(response.status)

        return sequence.classify(
            status: response.status,
            headers: response.headers,
            errorBody: succeeded ? nil : response.body,
            readAt: readAt
        )
    }
}
