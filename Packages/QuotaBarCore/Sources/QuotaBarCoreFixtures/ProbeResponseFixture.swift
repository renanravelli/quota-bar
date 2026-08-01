import Foundation

public enum ProbeResponseFixture {
    public enum Headers {
        public static let absent: [String: String] = [:]
        public static let retryAfterAsHTTPDate = ["Retry-After": "Wed, 21 Oct 2026 07:28:00 GMT"]

        public static func retryAfter(seconds: Int) -> [String: String] {
            ["retry-after": "\(seconds)"]
        }

        public static func retryAfterInUpperCase(seconds: Int) -> [String: String] {
            ["Retry-After": "\(seconds)"]
        }
    }

    public enum ErrorBody {
        public static let policyRestriction = body(
            type: "permission_error",
            message: "This credential is only authorized for use with Claude Code"
        )

        public static let expiredCredential = body(
            type: "authentication_error",
            message: "OAuth token has expired. Generate a new one with claude setup-token"
        )

        public static let revokedCredential = body(
            type: "authentication_error",
            message: "This credential has been revoked"
        )

        public static let unrecognized = body(
            type: "authentication_error",
            message: "invalid bearer token"
        )

        public static let empty = Data()
        public static let unreadable = Data([0xFF, 0xFE, 0x00, 0x01])
        public static let notJSON = Data("<html><body>403 Forbidden</body></html>".utf8)
        public static let unexpectedShape = Data(#"{"detail":"forbidden","code":403}"#.utf8)

        public static func withCanary(_ canary: String) -> Data {
            body(type: "authentication_error", message: "request denied for token \(canary)")
        }

        private static func body(type: String, message: String) -> Data {
            Data(#"{"type":"error","error":{"type":"\#(type)","message":"\#(message)"}}"#.utf8)
        }
    }
}
