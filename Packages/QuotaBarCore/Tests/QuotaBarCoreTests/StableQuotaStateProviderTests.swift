import Foundation
import QuotaBarCoreFixtures
import Testing
import os

@testable import QuotaBarCore

private final class EmissionLog: Sendable {
    private let states = OSAllocatedUnfairLock(initialState: [QuotaState]())

    var all: [QuotaState] { states.withLock { $0 } }

    func collect(_ provider: StableQuotaStateProvider) -> Task<Void, Never> {
        let stream = provider.states
        return Task { [states] in
            for await state in stream {
                states.withLock { $0.append(state) }
            }
        }
    }
}

@Suite("Modo de estado estável, fora do produto distribuído")
struct StableQuotaStateProviderTests {
    private static func observe(_ provider: StableQuotaStateProvider) async -> [QuotaState] {
        let log = EmissionLog()
        let collecting = log.collect(provider)
        try? await Task.sleep(for: .milliseconds(60))
        collecting.cancel()
        return log.all
    }

    @Test("REQ-23: o estado é emitido uma vez, sem rotação nem alteração espontânea")
    func theStateIsEmittedOnceAndNeverRotates() async throws {
        let emitted = await Self.observe(StableQuotaStateProvider())

        #expect(emitted.count == 1)
        #expect(emitted.first?.snapshot?.readSequence == 1)
        #expect(emitted.first?.cycle?.cadence.nature == .base)
    }

    @Test("AC-29 de QB-APP-002: o reset é ajustável para menos de uma hora")
    func theResetIsControllableBelowOneHour() async throws {
        let readAt = Date(timeIntervalSince1970: 1_700_000_000)
        let provider = StableQuotaStateProvider(resetsIn: .seconds(1_500), readAt: readAt)

        let emitted = await Self.observe(provider)

        let snapshot = try #require(emitted.first?.snapshot)
        let remaining = try #require(snapshot.fiveHour.resetsAt).timeIntervalSince(readAt)
        #expect(remaining == 1_500)
        #expect(remaining < 3_600)
    }

    @Test("REQ-23: observar o modo estável não pede leitura nem muda o regime")
    func observingTheStableModeChangesNothing() async {
        let provider = StableQuotaStateProvider()

        await provider.refreshNow()
        await provider.setViewerObserving(true)

        let emitted = await Self.observe(provider)
        #expect(emitted.count == 1)
    }
}
