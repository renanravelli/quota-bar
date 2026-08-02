import Foundation
import QuotaBarTransport
import Testing

@testable import QuotaBar

@MainActor
@Suite("Superfície de configuração montada pelo aplicativo")
struct CredentialSetupCompositionTests {
    private static let reading = ProbeHTTPResponse(
        status: 200,
        headers: [
            "anthropic-ratelimit-unified-5h-utilization": "0.42",
            "anthropic-ratelimit-unified-5h-reset": "1700003600",
            "anthropic-ratelimit-unified-7d-utilization": "0.19",
            "anthropic-ratelimit-unified-7d-reset": "1700086400"
        ],
        body: Data(#"{"id":"msg_1"}"#.utf8)
    )

    private static let refusal = ProbeHTTPResponse(
        status: 401,
        headers: [:],
        body: Data(#"{"type":"error","error":{"type":"authentication_error","message":"invalid bearer token"}}"#.utf8)
    )

    private static func model(
        store: RecordingCredentialStore,
        transport: StubProbeTransport,
        version: String? = "2.1.220 (Claude Code)",
        credentialDidChange: CredentialChangeSpy = CredentialChangeSpy()
    ) -> CredentialSetupModel {
        CredentialSetupFactory.make(
            credentials: store,
            transport: transport,
            environment: StubClaudeCodeEnvironment(version: version),
            spawner: UnavailablePseudoTerminal(),
            credentialDidChange: credentialDidChange.notify
        )
    }

    @Test("a superfície que o aplicativo monta verifica por leitura real e grava")
    func theSurfaceTheAppBuildsVerifiesAndStores() async {
        let store = RecordingCredentialStore()
        let transport = StubProbeTransport(Self.reading)
        let changed = CredentialChangeSpy()
        let model = Self.model(
            store: store,
            transport: transport,
            credentialDidChange: changed
        )

        await model.refresh()
        #expect(model.content.saveAvailability == .available)

        await model.save(credentialCanary)

        #expect(transport.sent.count == 1)
        #expect(model.stage == .configured)
        #expect(await store.holds(credentialCanary))
        #expect(await changed.notifications == 1)
    }

    @Test("a superfície que o aplicativo monta recusa sem gravar quando a origem recusa")
    func theSurfaceTheAppBuildsStoresNothingOnRefusal() async {
        let store = RecordingCredentialStore()
        let transport = StubProbeTransport(Self.refusal)
        let model = Self.model(store: store, transport: transport)

        await model.refresh()
        await model.save(credentialCanary)

        #expect(transport.sent.count == 1)
        #expect(model.stage == .refused)
        #expect(await store.isPopulated == false)
        #expect(model.message?.action == .generateNewCredential)
    }

    @Test("sem Claude Code descoberto, a superfície bloqueia e nada é requisitado")
    func theSurfaceTheAppBuildsBlocksWithoutClaudeCode() async {
        let store = RecordingCredentialStore()
        let transport = StubProbeTransport(Self.reading)
        let model = Self.model(store: store, transport: transport, version: nil)

        await model.refresh()
        await model.save(credentialCanary)

        #expect(model.stage == .blockedByPrecondition)
        #expect(model.content.saveAvailability != .available)
        #expect(transport.sent.isEmpty)
        #expect(await store.storeCount == 0)
    }
}
