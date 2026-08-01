import Foundation

public struct SubscriptionToken: Sendable,
                                 CustomStringConvertible,
                                 CustomDebugStringConvertible,
                                 CustomReflectable {
    private static let expectedPrefix = "sk-ant-oat01-"
    private static let redaction = "SubscriptionToken(redigido)"
    private static let whitespace = CharacterSet.whitespacesAndNewlines

    private let value: String

    public init?(pasted: String) {
        let trimmed = pasted.trimmingCharacters(in: Self.whitespace)
        let hasInteriorWhitespace = trimmed.unicodeScalars.contains(where: Self.whitespace.contains)
        guard trimmed.hasPrefix(Self.expectedPrefix), !hasInteriorWhitespace else { return nil }
        value = trimmed
    }

    public var description: String { Self.redaction }

    public var debugDescription: String { Self.redaction }

    public var customMirror: Mirror { Mirror(self, children: []) }

    public func withValue<T>(_ body: (String) throws -> T) rethrows -> T {
        try body(value)
    }
}
