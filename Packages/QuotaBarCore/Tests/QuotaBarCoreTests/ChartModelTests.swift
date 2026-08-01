import Foundation
import Testing
@testable import QuotaBarCore

private let epoch = Date(timeIntervalSince1970: 1_780_000_000)

private enum DomainSources {
    static let directory = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Sources")
        .appending(path: "QuotaBarCore")

    static func all() throws -> [String: String] {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }

        return try files.reduce(into: [:]) { sources, file in
            sources[file.lastPathComponent] = try String(contentsOf: file, encoding: .utf8)
        }
    }
}

private func basis(lastSampleAt: Date) -> ProjectionBasis {
    ProjectionBasis(
        sampleCount: 6,
        firstSampleAt: lastSampleAt.addingTimeInterval(-3_600),
        lastSampleAt: lastSampleAt,
        coveredFractionOfElapsedWindow: 0.8,
        resetInstantKnown: true
    )
}

@Suite("Modelo de gráfico do domínio")
struct ChartModelTests {
    @Test("nenhum arquivo do domínio importa a interface nem a biblioteca de gráficos")
    func theDomainImportsNoInterface() throws {
        let sources = try DomainSources.all()

        #expect(sources["ChartModel.swift"] != nil)
        #expect(sources.count > 20, "a varredura não encontrou o domínio")
        for (file, contents) in sources {
            #expect(!contents.contains("import SwiftUI"), "\(file) importa a interface")
            #expect(!contents.contains("import Charts"), "\(file) importa a biblioteca de gráficos")
        }
    }

    @Test("balde sem observação é marca de ausência, e ausência não é o mesmo que medido em zero")
    func absenceIsNotAMeasuredZero() {
        let bucket = BucketKey(start: epoch, size: .hour)

        #expect(ChartMark.absence(bucket) != ChartMark.measured(bucket, 0))
        #expect(ChartMark.measured(bucket, 0) == ChartMark.measured(bucket, 0))

        let series = ChartSeries(
            unit: .tokens,
            model: ModelIdentity(recorded: "claude-opus-5"),
            marks: [.measured(bucket, 0), .absence(bucket)]
        )
        #expect(Set(series.marks).count == 2)
    }

    @Test("só a projeção que projeta esgotamento desenha continuação")
    func onlyAProjectedExhaustionDrawsATrail() {
        let observed = basis(lastSampleAt: epoch)
        let refusals: [Projection] = [
            .unavailable(.seriesBeginsAtFirstReading),
            .exhausted(resetsAt: epoch.addingTimeInterval(600)),
            .insufficientSample(.quantity(observed: 2, required: 3)),
            .noObservedConsumption(ratePerHour: 0, basis: observed),
            .resetsBeforeExhausting(resetsAt: epoch.addingTimeInterval(600), ratePerHour: 4, basis: observed)
        ]

        for refusal in refusals {
            #expect(ProjectionTrail(of: refusal) == nil)
        }
        #expect(
            ProjectionTrail(
                of: .projected(
                    ProjectedExhaustion(ratePerHour: 12, at: epoch.addingTimeInterval(7_200), basis: observed)
                )
            ) != nil
        )
    }

    @Test("a continuação começa na última amostra observada e leva a base junto")
    func theTrailStartsAtTheLastSampleAndCarriesItsBasis() throws {
        let observed = basis(lastSampleAt: epoch)
        let reaching = epoch.addingTimeInterval(7_200)
        let trail = try #require(
            ProjectionTrail(
                of: .projected(ProjectedExhaustion(ratePerHour: 12, at: reaching, basis: observed))
            )
        )

        #expect(trail.anchoredAt == epoch)
        #expect(trail.reaching == reaching)
        #expect(trail.basis == observed)
    }

    @Test("a marcação de frescor envelhece contra o instante de renderização, sem relógio próprio")
    func freshnessAgesAgainstTheRenderInstant() {
        let cadence = Duration.seconds(180)
        let fresh = SeriesFreshness.of(
            lastObservedAt: epoch,
            at: epoch.addingTimeInterval(300),
            maxIdleCadenceSinceReading: cadence
        )
        let stale = SeriesFreshness.of(
            lastObservedAt: epoch,
            at: epoch.addingTimeInterval(1_200),
            maxIdleCadenceSinceReading: cadence
        )

        #expect(fresh == .fresh(age: .seconds(300)))
        #expect(stale == .stale(age: .seconds(1_200)))
        #expect(SeriesFreshness.of(lastObservedAt: nil, at: epoch, maxIdleCadenceSinceReading: cadence) == .neverObserved)
    }
}
