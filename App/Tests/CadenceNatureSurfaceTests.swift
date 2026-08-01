import Foundation
import Testing

@testable import QuotaBar
@testable import QuotaBarCore

enum CadenceSurface {
    static let readAt = Date(timeIntervalSince1970: 1_700_000_000)
    static let interval: Duration = .seconds(180)

    static func state(
        nature: ScheduledNature = .base,
        deferralDeadline: Date = .distantFuture,
        interval: Duration = CadenceSurface.interval,
        cycleID: UInt64 = 1
    ) -> QuotaState {
        let snapshot = QuotaSnapshot(
            fiveHour: WindowReading(
                utilization: Utilization(originPercent: 30)!,
                resetsAt: readAt.addingTimeInterval(7_200),
                status: .allowed
            ),
            sevenDay: WindowReading(utilization: nil, resetsAt: nil, status: .allowed),
            overallStatus: .allowed,
            nextResetAt: nil,
            bindingWindow: .window(.fiveHour),
            fallbackPercentage: nil,
            overage: OverageInfo(status: nil, disabledReason: nil),
            readSequence: 1,
            readAt: readAt,
            source: .primaryProbe
        )!

        return QuotaState(
            credentialPresent: true,
            snapshot: snapshot,
            lastAttempt: .succeeded(at: readAt),
            cycle: TestCycle.scheduled(interval, nature: nature, id: cycleID, deferralDeadline: deferralDeadline),
            maxIdleCadenceSinceReading: .seconds(1_800),
            source: .primaryProbe
        )
    }

    static func content(of state: QuotaState, at now: Date, deferralLatch: inout DeferralLatch) -> PanelContent {
        var staleLatch = StaleLatch()
        return PanelContentBuilder.build(
            state: state,
            indicator: IndicatorStateResolver.resolve(state: state, latch: &staleLatch, now: now),
            at: now,
            deferralLatch: &deferralLatch
        )
    }

    static func content(of state: QuotaState, at now: Date) -> PanelContent {
        var latch = DeferralLatch()
        return content(of: state, at: now, deferralLatch: &latch)
    }

    static func frames(over states: [(state: QuotaState, elapsed: [TimeInterval])]) -> [PanelContent] {
        var latch = DeferralLatch()
        var built: [PanelContent] = []
        for entry in states {
            for elapsed in entry.elapsed {
                built.append(content(of: entry.state, at: readAt.addingTimeInterval(elapsed), deferralLatch: &latch))
            }
        }
        return built
    }

    static func frames(of state: QuotaState, from: TimeInterval, to: TimeInterval, step: TimeInterval) -> [PanelContent] {
        frames(over: [(state, Array(stride(from: from, through: to, by: step)))])
    }

    static let fourNatures: [(name: String, state: QuotaState)] = [
        ("ritmo base", state(nature: .base)),
        ("ociosidade", state(nature: .idle)),
        ("falha", state(nature: .widenedByFailure)),
        ("adiada", state(nature: .base, deferralDeadline: readAt.addingTimeInterval(60)))
    ]
}

private struct TextOnly: Hashable {
    let cadence: String?
    let rest: [String?]
    let litSegments: [Int]

    init(_ content: PanelContent) {
        cadence = content.cadence
        rest = [
            content.situation, content.selection, content.source,
            content.credentialNotice, content.sourceChangeNotice, content.fixtureNotice,
            content.fiveHour.utilization, content.fiveHour.countdown, content.fiveHour.reset,
            content.sevenDay.utilization, content.sevenDay.countdown, content.sevenDay.reset
        ] + content.pendencies + content.actionTitles + content.contingencyLosses
        litSegments = [content.fiveHour.litSegments, content.sevenDay.litSegments]
    }

    private init(cadence: String?, rest: [String?], litSegments: [Int]) {
        self.cadence = cadence
        self.rest = rest
        self.litSegments = litSegments
    }

    var withoutTheCadenceLine: TextOnly {
        TextOnly(cadence: nil, rest: rest, litSegments: litSegments)
    }
}

@Suite("Distinção das naturezas de cadência")
struct CadenceNatureSurfaceTests {
    @Test("QB-APP-002 AC-18: as quatro naturezas se distinguem com a cor removida do painel")
    func theFourNaturesAreDistinctWithoutColor() throws {
        let observed = CadenceSurface.readAt.addingTimeInterval(90)
        let contents = CadenceSurface.fourNatures.map { CadenceSurface.content(of: $0.state, at: observed) }

        let lines = try contents.map { try #require($0.cadence) }
        #expect(Set(lines).count == 4, "duas naturezas produziram a mesma linha de cadência")
        #expect(Set(contents.map(TextOnly.init)).count == 4)
        #expect(contents.map(\.fiveHour.tint).allSatisfy { $0 == contents[0].fiveHour.tint })
    }

    @Test("QB-APP-002 AC-18: ignorando a barra inteira, a linha de cadência continua distinguindo as quatro")
    func ignoringTheBarLosesNoInformation() {
        let observed = CadenceSurface.readAt.addingTimeInterval(90)
        let contents = CadenceSurface.fourNatures.map { CadenceSurface.content(of: $0.state, at: observed) }

        let withoutTheBar = contents.map(TextOnly.init)
        #expect(Set(withoutTheBar).count == 4, "sem a barra, duas naturezas ficaram indistinguíveis")
        #expect(
            Set(withoutTheBar.map(\.withoutTheCadenceLine)).count == 1,
            "algo além da linha de cadência estava distinguindo as naturezas"
        )
    }

    @Test("QB-APP-002 AC-18: a barra representa o progresso até a próxima leitura nas quatro naturezas")
    func theBarShowsProgressInEveryNature() throws {
        let elapsed: TimeInterval = 90

        for nature in CadenceSurface.fourNatures {
            let bar = try #require(
                CadenceSurface.content(of: nature.state, at: CadenceSurface.readAt.addingTimeInterval(elapsed)).cadenceBar
            )
            #expect(abs(bar.progress - elapsed / 180) < 0.001, "a barra não representa o progresso em \(nature.name)")
        }
    }

    @Test("QB-APP-002 AC-18: as marcas continuam distintas como reforço permitido")
    func theMarksRemainDistinctAsPermittedReinforcement() {
        let observed: [Cadence.Nature] = [.base, .idle, .widenedByFailure, .deferredBySystem]

        #expect(Set(observed.map(CadenceMark.mark(for:))).count == 4)
        #expect(CadenceMark.mark(for: .base) == CadenceMark.none)
    }

    @Test("QB-APP-002 AC-34: com o estado constante, só o preenchimento muda na barra")
    func onlyTheFillMovesWhileTheStateIsConstant() throws {
        let bars = try CadenceSurface
            .frames(of: CadenceSurface.state(nature: .idle), from: 0, to: 10, step: 0.5)
            .map { try #require($0.cadenceBar) }

        #expect(bars.allSatisfy { $0.nature == .idle })
        #expect(Set(bars.map(\.mark)).count == 1, "a marca mudou sem que a natureza mudasse")
        #expect(Set(bars.map(\.progress)).count == bars.count, "o preenchimento não se moveu")
    }

    @Test("QB-APP-002 AC-34: barra e texto mudam juntos quando a natureza muda, com e sem estado novo")
    func theBarAndTheTextChangeTogether() throws {
        let crossingWithoutNewState = CadenceSurface.frames(
            of: CadenceSurface.state(deferralDeadline: CadenceSurface.readAt.addingTimeInterval(120)),
            from: 60,
            to: 180,
            step: 5
        )
        let stateChange = CadenceSurface.frames(over: [
            (CadenceSurface.state(nature: .base), [60, 90]),
            (CadenceSurface.state(nature: .widenedByFailure, cycleID: 2), [120, 150])
        ])

        for frames in [crossingWithoutNewState, stateChange] {
            let natures = try frames.map { try #require($0.cadenceBar).nature }
            let lines = try frames.map { try #require($0.cadence) }

            for (nature, line) in zip(natures, lines) {
                #expect(
                    line == PanelText.cadenceLine(Cadence(interval: CadenceSurface.interval, nature: nature)!),
                    "a barra apresentou a variante de \(nature) junto do texto \(line)"
                )
            }
            #expect(Set(natures).count == 2, "o percurso não atravessou a mudança de natureza")
            #expect(
                changeIndices(of: natures) == changeIndices(of: lines),
                "a barra e o texto mudaram em quadros diferentes"
            )
        }
    }

    @Test("QB-APP-002 AC-35: passado o instante previsto, o preenchimento chega a cheio e para")
    func theFillSaturatesAndStops() throws {
        let frames = CadenceSurface.frames(of: CadenceSurface.state(), from: 0, to: 360, step: 5)
        let bars = try frames.map { try #require($0.cadenceBar) }
        let progress = bars.map(\.progress)

        #expect(progress.first == 0)
        #expect(progress == progress.sorted(), "o preenchimento recuou ou reiniciou")
        #expect(progress.allSatisfy { $0 <= 1 }, "o preenchimento transbordou")
        #expect(progress.last == 1)
        #expect(progress.drop { $0 < 1 }.allSatisfy { $0 == 1 }, "o preenchimento voltou a andar depois de saturar")
        #expect(Set(bars.map(\.nature)).count == 1, "a natureza mudou no percurso e a barra não é só preenchimento")
    }

    @Test("QB-APP-002 REQ-11: cheio e parado não identifica adiamento — a espera por falha satura igual")
    func saturationDoesNotIdentifyDeferral() throws {
        let frames = CadenceSurface.frames(of: CadenceSurface.state(nature: .widenedByFailure), from: 180, to: 360, step: 5)
        let bars = try frames.map { try #require($0.cadenceBar) }

        #expect(bars.allSatisfy { $0.progress == 1 }, "a cadência ampliada por falha não saturou")
        #expect(bars.allSatisfy { $0.nature == .widenedByFailure })
        #expect(frames.allSatisfy { $0.cadence?.contains("ampliado por falha") == true })
    }

    private func changeIndices<Value: Equatable>(of values: [Value]) -> [Int] {
        zip(values, values.dropFirst()).enumerated().compactMap { index, pair in
            pair.0 == pair.1 ? nil : index + 1
        }
    }
}
