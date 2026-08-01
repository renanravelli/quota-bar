import Foundation

public enum ProbeModel {
    public static let ordered = [
        "claude-haiku-4-5",
        "claude-sonnet-5",
        "claude-opus-5"
    ]
}

public enum ProbeRequestFactory {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    public static func make(
        model: String,
        claudeCodeVersion: String,
        token: SubscriptionToken
    ) -> ProbeRequest {
        ProbeRequest(
            url: endpoint,
            headers: token.withValue { headers(authorizedWith: $0, claudeCodeVersion: claudeCodeVersion) },
            body: body(model: model)
        )
    }

    private static func headers(authorizedWith value: String, claudeCodeVersion: String) -> [String: String] {
        [
            "authorization": "Bearer \(value)",
            "anthropic-version": "2023-06-01",
            "anthropic-beta": "oauth-2025-04-20",
            "content-type": "application/json",
            "user-agent": "claude-code/\(claudeCodeVersion)"
        ]
    }

    private static func body(model: String) -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return (try? encoder.encode(Payload(model: model))) ?? Data()
    }

    private struct Payload: Encodable {
        struct Message: Encodable {
            let role = "user"
            let content = "."
        }

        let model: String
        let maxTokens = 1
        let messages = [Message()]
    }
}
