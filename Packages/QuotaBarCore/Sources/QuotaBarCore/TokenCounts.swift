public enum TokenCounter: Sendable, Hashable, CaseIterable {
    case input
    case output
    case cacheRead
    case cacheCreation
}

public struct TokenTotal: Sendable, Hashable {
    public let value: Int
    public let aggregates: Set<TokenCounter>

    public init(value: Int, aggregates: Set<TokenCounter>) {
        self.value = value
        self.aggregates = aggregates
    }
}

public struct TokenCounts: Sendable, Hashable, AdditiveArithmetic {
    public static let zero = TokenCounts(input: 0, output: 0, cacheRead: 0, cacheCreation: 0)

    public let input: Int
    public let output: Int
    public let cacheRead: Int
    public let cacheCreation: Int

    public init(input: Int, output: Int, cacheRead: Int, cacheCreation: Int) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheCreation = cacheCreation
    }

    public subscript(counter: TokenCounter) -> Int {
        switch counter {
        case .input: input
        case .output: output
        case .cacheRead: cacheRead
        case .cacheCreation: cacheCreation
        }
    }

    public var total: TokenTotal {
        TokenTotal(
            value: input + output + cacheRead + cacheCreation,
            aggregates: Set(TokenCounter.allCases)
        )
    }

    public static func + (lhs: TokenCounts, rhs: TokenCounts) -> TokenCounts {
        TokenCounts(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheCreation: lhs.cacheCreation + rhs.cacheCreation
        )
    }

    public static func - (lhs: TokenCounts, rhs: TokenCounts) -> TokenCounts {
        TokenCounts(
            input: lhs.input - rhs.input,
            output: lhs.output - rhs.output,
            cacheRead: lhs.cacheRead - rhs.cacheRead,
            cacheCreation: lhs.cacheCreation - rhs.cacheCreation
        )
    }
}
