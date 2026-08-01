import Foundation

struct TranscriptLine: Decodable {
    struct Message: Decodable {
        struct Usage: Decodable {
            struct Iteration: Decodable {
                let model: String?
                let inputTokens: Int?
                let outputTokens: Int?
                let cacheReadInputTokens: Int?
                let cacheCreationInputTokens: Int?

                enum CodingKeys: String, CodingKey {
                    case model
                    case inputTokens = "input_tokens"
                    case outputTokens = "output_tokens"
                    case cacheReadInputTokens = "cache_read_input_tokens"
                    case cacheCreationInputTokens = "cache_creation_input_tokens"
                }
            }

            let inputTokens: Int?
            let outputTokens: Int?
            let cacheReadInputTokens: Int?
            let cacheCreationInputTokens: Int?
            let iterations: [Iteration]?

            enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case outputTokens = "output_tokens"
                case cacheReadInputTokens = "cache_read_input_tokens"
                case cacheCreationInputTokens = "cache_creation_input_tokens"
                case iterations
            }
        }

        let id: String?
        let model: String?
        let usage: Usage?
    }

    let message: Message?
    let requestId: String?
    let uuid: String?
    let timestamp: String?
    let version: String?
}
