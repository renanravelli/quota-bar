public enum ModelIdentity: Sendable, Hashable {
    case model(String)
    case nonModel(String)

    public init(recorded identifier: String) {
        self = Self.isPlaceholder(identifier) ? .nonModel(identifier) : .model(identifier)
    }

    public var recordedIdentifier: String {
        switch self {
        case .model(let identifier), .nonModel(let identifier): identifier
        }
    }

    public var namesAModel: Bool {
        if case .model = self { return true }
        return false
    }

    private static func isPlaceholder(_ identifier: String) -> Bool {
        identifier.hasPrefix("<") && identifier.hasSuffix(">") && identifier.count > 2
    }
}

extension ModelIdentity: Comparable {
    public static func < (lhs: ModelIdentity, rhs: ModelIdentity) -> Bool {
        (lhs.namesAModel ? 0 : 1, lhs.recordedIdentifier) < (rhs.namesAModel ? 0 : 1, rhs.recordedIdentifier)
    }
}
