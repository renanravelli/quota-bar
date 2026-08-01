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
            credentialDidChange: credentialDidChange
        )
    }

    static func make(
        credentials: any CredentialStoring,
        transport: any ProbeTransporting,
        environment: any ClaudeCodeEnvironment,
        credentialDidChange: @escaping @Sendable () async -> Void
    ) -> CredentialSetupModel {
        let locator = ClaudeCodeLocator(environment: environment)

        return CredentialSetupModel(
            store: credentials,
            verifier: ProbeCredentialVerifier(
                probe: QuotaProbe(transport: transport, credentials: credentials),
                locator: locator
            ),
            claudeCode: { await locator.discover() },
            credentialDidChange: credentialDidChange
        )
    }
}
