import Foundation

public struct URLSessionProbeTransport: ProbeTransporting {
    public static let timeout: TimeInterval = 15

    private let session: UncheckedSendable<URLSession>

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        session = UncheckedSendable(URLSession(configuration: configuration))
    }

    public func send(_ request: ProbeRequest) async throws -> ProbeHTTPResponse {
        var outgoing = URLRequest(url: request.url)
        outgoing.httpMethod = "POST"
        outgoing.httpBody = request.body
        for (name, value) in request.headers {
            outgoing.setValue(value, forHTTPHeaderField: name)
        }

        let (data, response) = try await session.value.data(for: outgoing)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        return ProbeHTTPResponse(status: http.statusCode, headers: Self.fields(of: http), body: data)
    }

    private static func fields(of response: HTTPURLResponse) -> [String: String] {
        var fields = [String: String](minimumCapacity: response.allHeaderFields.count)
        for (name, value) in response.allHeaderFields {
            guard let name = name as? String, let value = value as? String else { continue }
            fields[name.lowercased()] = value
        }
        return fields
    }
}
