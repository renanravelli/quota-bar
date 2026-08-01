import Foundation

public protocol DateProviding: Sendable {
    var now: Date { get }
}

public struct SystemDate: DateProviding {
    public init() {}

    public var now: Date { Date() }
}
