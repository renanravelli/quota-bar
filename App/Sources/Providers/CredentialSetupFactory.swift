import QuotaBarCore
import QuotaBarTransport

enum CredentialSetupWindow {
    static let id = "credential-setup"
}

@MainActor
enum CredentialSetupFactory {
    static func make(credentialDidChange: @escaping @Sendable () async -> Void) -> CredentialSetupModel {
        make(
            credentials: KeychainCredentialStore(),
            transport: URLSessionProbeTransport(),
            environment: SystemClaudeCodeEnvironment(),
            spawner: SystemPseudoTerminal(),
            credentialDidChange: credentialDidChange
        )
    }

    static func make(
        credentials: any CredentialStoring,
        transport: any ProbeTransporting,
        environment: any ClaudeCodeEnvironment,
        spawner: any PseudoTerminalSpawning,
        credentialDidChange: @escaping @Sendable () async -> Void
    ) -> CredentialSetupModel {
        let locator = ClaudeCodeLocator(environment: environment)

        return CredentialSetupModel(
            store: credentials,
            verifier: ProbeCredentialVerifier(
                probe: QuotaProbe(transport: transport, credentials: credentials),
                locator: locator
            ),
            acquirer: SetupTokenCredentialAcquirer(
                discover: { await locator.discover() },
                spawner: spawner
            ),
            claudeCode: { await locator.discover() },
            credentialDidChange: credentialDidChange
        )
    }
}
