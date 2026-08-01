import Foundation

enum ProbeModelAvailability {
    static let successStatus = 200...299

    static func isModelUnavailable(status: Int, body: Data) -> Bool {
        guard status == 404 || status == 400 else { return false }
        guard let message = message(in: body)?.lowercased() else { return false }
        return message.contains("model")
    }

    private static func message(in body: Data) -> String? {
        guard !body.isEmpty else { return nil }
        return (try? JSONDecoder().decode(Envelope.self, from: body))?.error.message
    }

    private struct Envelope: Decodable {
        struct Failure: Decodable {
            let message: String
        }

        let error: Failure
    }
}
