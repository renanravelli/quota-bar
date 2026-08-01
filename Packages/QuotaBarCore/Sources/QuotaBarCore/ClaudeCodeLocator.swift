public actor ClaudeCodeLocator {
    private var resolver: ClaudeCodeVersionResolver

    public init(environment: any ClaudeCodeEnvironment) {
        resolver = ClaudeCodeVersionResolver(environment: environment)
    }

    public func discover() -> ClaudeCodeDiscovery {
        resolver.resolve()
    }
}
