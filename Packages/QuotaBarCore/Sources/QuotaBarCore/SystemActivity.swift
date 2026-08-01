public struct SystemActivityAssertion: Sendable {
    private let release: @Sendable () -> Void

    public init(release: @escaping @Sendable () -> Void) {
        self.release = release
    }

    public func end() {
        release()
    }
}

public protocol SystemActivityAsserting: Sendable {
    func beginProbeActivity() -> SystemActivityAssertion
}
