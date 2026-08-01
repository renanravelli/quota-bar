import Foundation
import Testing

@testable import QuotaBar
@testable import QuotaBarCore

enum Journey {
    static let readAt = Date(timeIntervalSince1970: 1_700_000_000)
    static let stalenessLimit: TimeInterval = 600
    static let cadence: Duration = .seconds(180)
    static let deferralDeadline = readAt.addingTimeInterval(270)

    static func state(
        deferralDeadline: Date = Journey.deferralDeadline,
        readAt: Date = Journey.readAt,
        cycleID: UInt64 = 1,
        readSequence: UInt64 = 1
    ) -> QuotaState {
        let snapshot = QuotaSnapshot(
            fiveHour: WindowReading(
                utilization: Utilization(originPercent: 30)!,
                resetsAt: readAt.addingTimeInterval(7_200),
                status: .allowed
            ),
            sevenDay: WindowReading(
                utilization: Utilization(originPercent: 12)!,
                resetsAt: readAt.addingTimeInterval(86_400),
                status: .allowed
            ),
            overallStatus: .allowed,
            nextResetAt: nil,
            bindingWindow: .window(.fiveHour),
            fallbackPercentage: nil,
            overage: OverageInfo(status: nil, disabledReason: nil),
            readSequence: readSequence,
            readAt: readAt,
            source: .primaryProbe
        )!

        return QuotaState(
            credentialPresent: true,
            snapshot: snapshot,
            lastAttempt: .succeeded(at: readAt),
            cycle: TestCycle.scheduled(cadence, id: cycleID, deferralDeadline: deferralDeadline),
            maxIdleCadenceSinceReading: .seconds(Int(stalenessLimit) / 2),
            source: .primaryProbe
        )
    }

    @MainActor
    static func openPanel(
        over state: QuotaState,
        clock: @escaping @Sendable () -> Date = { Journey.readAt },
        provider: RecordingQuotaStateProvider = RecordingQuotaStateProvider()
    ) -> IndicatorPresenter {
        let presenter = IndicatorPresenter(provider: provider, clock: clock, reduceMotion: { .off })
        presenter.receive(state)
        presenter.panelDidOpen()
        return presenter
    }

    static func allStrings(of content: PanelContent) -> [String] {
        var strings = [content.situation, content.quitTitle]
        strings += [content.selection, content.cadenceLine, content.source].compactMap { $0 }
        strings += [content.credentialNotice, content.sourceChangeNotice, content.fixtureNotice].compactMap { $0 }
        strings += content.contingencyLosses + content.pendencies + content.actionTitles
        for row in [content.fiveHour, content.sevenDay] {
            strings += [row.name] + [row.utilization, row.reset, row.countdown].compactMap { $0 } + row.absences
        }
        return strings
    }

    static func displayedMinutes(in situation: String) -> Int? {
        if situation.contains("há menos de um minuto") { return 0 }
        guard let range = situation.range(of: #"há (\d+) minutos?"#, options: .regularExpression) else { return nil }
        return Int(situation[range].filter(\.isNumber))
    }

    static func isMarkedStale(_ situation: String) -> Bool {
        situation.contains("possivelmente desatualizado")
    }
}

@MainActor
@Suite("Instante único de renderização")
struct RenderInstantTests {
    @Test("QB-APP-001 AC-57: a idade acompanha o relógio de 3 a 20 minutos, sem estado novo fornecido")
    func theAgeFollowsTheClockWhileThePanelIsOpen() {
        let presenter = Journey.openPanel(over: Journey.state(deferralDeadline: .distantFuture))

        let ages = stride(from: 180.0, through: 1_200.0, by: 20.0).map { elapsed in
            (
                elapsed: elapsed,
                displayed: Journey.displayedMinutes(
                    in: presenter.panelContent(at: Journey.readAt.addingTimeInterval(elapsed)).situation
                )
            )
        }

        for sample in ages {
            #expect(
                sample.displayed == Int(sample.elapsed) / 60,
                "aos \(sample.elapsed) s a idade exibida foi \(String(describing: sample.displayed))"
            )
        }
        #expect(Set(ages.map(\.displayed)).count == 18, "a idade congelou em vez de acompanhar o relógio")
    }

    @Test("QB-APP-001 AC-57: marcação e idade nunca discordam, inclusive no instante do cruzamento")
    func theMarkingAndTheAgeNeverDisagree() {
        let presenter = Journey.openPanel(over: Journey.state(deferralDeadline: .distantFuture))
        let limit = Int(Journey.stalenessLimit) / 60

        let frames = stride(from: 180.0, through: 1_200.0, by: 1.0).map { elapsed in
            presenter.panelContent(at: Journey.readAt.addingTimeInterval(elapsed)).situation
        }

        for situation in frames {
            let displayed = Journey.displayedMinutes(in: situation) ?? -1
            if Journey.isMarkedStale(situation) {
                #expect(displayed >= limit, "marcação de desatualizado com idade de \(displayed) min: \(situation)")
            } else {
                #expect(displayed <= limit, "idade de \(displayed) min sem marcação de desatualizado: \(situation)")
            }
        }

        #expect(frames.contains(where: Journey.isMarkedStale), "o percurso não atravessou o limite")
        #expect(frames.contains { !Journey.isMarkedStale($0) }, "o percurso já começou desatualizado")
    }

    @Test("QB-APP-002 AC-21: em regime só os cinco conteúdos dirigidos pelo tempo mudam, e os cruzamentos aparecem")
    func onlyTheFiveTimeDrivenContentsChangeInRegime() throws {
        let presenter = Journey.openPanel(over: Journey.state())
        let frames = stride(from: 120.0, through: 900.0, by: 5.0).map { elapsed in
            presenter.panelContent(at: Journey.readAt.addingTimeInterval(elapsed))
        }

        let invariants = frames.map(RegimeInvariant.init)
        #expect(invariants.allSatisfy { $0 == invariants[0] }, "algo fora dos cinco conteúdos mudou em regime")

        let countdowns = frames.map(\.fiveHour.countdown)
        let progress = try frames.map { try #require($0.cadence).progress }
        let markings = frames.map { Journey.isMarkedStale($0.situation) }
        let ages = frames.map { Journey.displayedMinutes(in: $0.situation) }
        let declarations = frames.map { $0.cadenceLine?.contains("adiada pelo sistema") == true }
        let reinforcements = try frames.map { try #require($0.cadence).reinforcement }

        #expect(Set(countdowns).count > 1, "a contagem regressiva não andou")
        #expect(Set(progress).count > 1, "o preenchimento não andou")
        #expect(Set(ages).count > 1, "a idade não andou")
        #expect(flips(of: markings) == 1, "a marcação de desatualizado não cruzou o limite exatamente uma vez")
        #expect(flips(of: declarations) == 1, "a declaração de adiamento não apareceu exatamente uma vez")
        #expect(markings.first == false && markings.last == true)
        #expect(declarations.first == false && declarations.last == true)

        #expect(
            changeIndices(of: reinforcements) == changeIndices(of: declarations),
            "a variante da barra mudou fora da atualização em que o texto passou a declarar o adiamento"
        )
        #expect(
            zip(reinforcements, declarations).allSatisfy { ($0 == .deferral) == $1 },
            "a barra apresentou a variante de uma natureza junto do texto de outra"
        )
    }

    private func flips(of values: [Bool]) -> Int {
        zip(values, values.dropFirst()).count { $0 != $1 }
    }

    private func changeIndices<Value: Equatable>(of values: [Value]) -> [Int] {
        zip(values, values.dropFirst()).enumerated().compactMap { index, pair in
            pair.0 == pair.1 ? nil : index + 1
        }
    }
}

private struct RegimeInvariant: Equatable {
    let rows: [[String]]
    let tints: [QuotaBarCore.RGBColor?]
    let litSegments: [Int]
    let cadenceInterval: Duration?
    let selection: String?
    let source: String?
    let notices: [String?]
    let pendencies: [String]
    let mascot: MascotExpression
    let actionTitles: [String]

    init(_ content: PanelContent) {
        rows = [content.fiveHour, content.sevenDay].map { row in
            [row.name, row.utilization, row.reset].compactMap { $0 } + row.absences
        }
        tints = [content.fiveHour.tint, content.sevenDay.tint]
        litSegments = [content.fiveHour.litSegments, content.sevenDay.litSegments]
        cadenceInterval = content.cadence?.cadence.interval
        selection = content.selection
        source = content.source
        notices = [content.credentialNotice, content.sourceChangeNotice, content.fixtureNotice]
        pendencies = content.pendencies + content.contingencyLosses
        mascot = content.mascot
        actionTitles = content.actionTitles
    }
}
