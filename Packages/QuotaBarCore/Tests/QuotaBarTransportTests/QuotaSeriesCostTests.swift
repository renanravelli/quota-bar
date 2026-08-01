import Foundation
import QuotaBarCore
import Testing
import os

@testable import QuotaBarTransport

final class InMemoryQuotaSampleLog: QuotaSampleLogging, Sendable {
    private let recorded = OSAllocatedUnfairLock(initialState: [QuotaSample]())

    func append(_ sample: QuotaSample) async {
        recorded.withLock { $0.append(sample) }
    }

    func load(since: Date) async -> QuotaSampleSeries {
        QuotaSampleSeries(recorded.withLock { $0.filter { $0.readAt >= since } })
    }
}

@Suite("Custo de rede da série, da taxa e da projeção")
struct QuotaSeriesCostTests {
    @Test("registrar cem amostras e projetar a cada uma não emite requisição nenhuma")
    func recordingAndProjectingEmitsNoRequest() async {
        let transport = RecordingTransport([CannedResponse.reading()])
        let log = InMemoryQuotaSampleLog()
        let windowStart = TestSample.instant("2026-08-01T09:00:00Z")
        var latch = ProjectionLatch()

        for index in 0..<100 {
            let readAt = windowStart.addingTimeInterval(Double(index + 1) * 180)
            await log.append(TestSample.at(readAt, sequence: UInt64(index + 1), fiveHour: "\(index).00"))

            let series = await log.load(since: windowStart)
            latch.update(
                with: series,
                window: .fiveHour,
                sinceResetAt: windowStart,
                maxIdleCadence: .seconds(900),
                now: readAt
            )
        }

        var projected = false
        if case .projected = latch.projection { projected = true }

        #expect(transport.sentCount == 0)
        #expect(projected)
    }
}
