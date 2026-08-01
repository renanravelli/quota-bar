import QuotaBarCore
import QuotaBarTransport

enum ProviderFactory {
    static let isFixtureFed = false

    static func make() -> any QuotaStateProviding {
        let lifecycle = ProbeLifecycle(
            observing: WorkspacePowerEventObserver(),
            activity: ProcessActivityAsserter(),
            time: SystemDate()
        )
        let credentials = KeychainCredentialStore()
        let provider = ProbingQuotaStateProvider(
            probe: QuotaProbe(transport: URLSessionProbeTransport(), credentials: credentials),
            credentials: credentials,
            environment: SystemClaudeCodeEnvironment(),
            lifecycle: lifecycle,
            store: FileQuotaSnapshotStore.applicationSupport
        )

        Task { await lifecycle.run() }
        Task { await provider.run() }

        return provider
    }
}
