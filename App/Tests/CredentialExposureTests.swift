import Foundation
import Testing

@testable import QuotaBar
@testable import QuotaBarCore

private let canary = "CANARIO-CREDENCIAL-NAO-DEVE-VAZAR"

private enum Sweep {
    static let readAt = Date(timeIntervalSince1970: 1_700_000_000)
    static let locale = Locale(identifier: "pt_BR")
    static let timeZone = TimeZone(identifier: "America/Sao_Paulo")!
    static let sources: [QuotaSource] = [.primaryProbe, .contingencyStatusLine]
    static let reasons = FailureReason.allCases

    static func snapshot(percent: String, source: QuotaSource, binding: BindingWindow?) -> QuotaSnapshot {
        QuotaSnapshot(
            fiveHour: WindowReading(
                utilization: Utilization(originPercent: Decimal(string: percent)!),
                resetsAt: readAt.addingTimeInterval(3_600),
                status: .unknown(canary)
            ),
            sevenDay: WindowReading(
                utilization: Utilization(originPercent: 41),
                resetsAt: nil,
                status: .unknown(canary)
            ),
            overallStatus: .unknown(canary),
            nextResetAt: nil,
            bindingWindow: binding,
            fallbackPercentage: nil,
            overage: OverageInfo(status: canary, disabledReason: canary),
            readSequence: 1,
            readAt: readAt,
            source: source
        )!
    }

    static func state(
        snapshot: QuotaSnapshot?,
        credentialPresent: Bool = true,
        lastAttempt: AttemptOutcome,
        source: QuotaSource
    ) -> QuotaState {
        QuotaState(
            credentialPresent: credentialPresent,
            snapshot: snapshot,
            lastAttempt: lastAttempt,
            cycle: TestCycle.scheduled(),
            maxIdleCadenceSinceReading: .seconds(180),
            source: source
        )
    }

    static func surfaces(
        _ state: QuotaState,
        afterSeconds seconds: TimeInterval
    ) -> (indicator: String, accessibility: String, panel: PanelContent) {
        var latch = StaleLatch()
        var deferral = DeferralLatch()
        let now = readAt.addingTimeInterval(seconds)
        let indicator = IndicatorStateResolver.resolve(state: state, latch: &latch, now: now)
        let source = state.source ?? state.snapshot?.source ?? .primaryProbe

        return (
            IndicatorTextFormatter.text(for: indicator),
            IndicatorAccessibilityLabel.text(for: indicator, source: source),
            PanelContentBuilder.build(
                state: state,
                indicator: indicator,
                at: now,
                deferralLatch: &deferral,
                previouslySeenSource: source == .primaryProbe ? .contingencyStatusLine : .primaryProbe,
                fixtureFed: true,
                locale: locale,
                timeZone: timeZone
            )
        )
    }

    static func allStrings(of panel: PanelContent) -> [String] {
        var strings: [String] = [panel.situation, panel.quitTitle]
        strings.append(contentsOf: [panel.selection, panel.cadence, panel.source].compactMap { $0 })
        strings.append(contentsOf: [panel.credentialNotice, panel.sourceChangeNotice, panel.fixtureNotice].compactMap { $0 })
        strings.append(contentsOf: panel.contingencyLosses)
        strings.append(contentsOf: panel.pendencies)
        strings.append(contentsOf: panel.actionTitles)
        for row in [panel.fiveHour, panel.sevenDay] {
            strings.append(row.name)
            strings.append(contentsOf: [row.utilization, row.reset, row.countdown].compactMap { $0 })
            strings.append(contentsOf: row.absences)
        }
        return strings
    }

    static func everyState() -> [(label: String, state: QuotaState, afterSeconds: TimeInterval)] {
        var cases: [(String, QuotaState, TimeInterval)] = []

        for source in sources {
            cases.append((
                "notConfigured/\(source)",
                state(snapshot: nil, credentialPresent: false, lastAttempt: .inProgress, source: source),
                60
            ))
            cases.append((
                "loading/\(source)",
                state(snapshot: nil, lastAttempt: .inProgress, source: source),
                60
            ))

            for reason in reasons {
                cases.append((
                    "failed(\(reason))/\(source)",
                    state(snapshot: nil, lastAttempt: .failed(reason), source: source),
                    60
                ))
            }

            for binding in [BindingWindow.window(.fiveHour), .unrecognized(canary), nil] {
                let ready = snapshot(percent: "42", source: source, binding: binding)
                cases.append((
                    "ready/\(source)/\(String(describing: binding))",
                    state(snapshot: ready, lastAttempt: .succeeded(at: readAt), source: source),
                    60
                ))
                cases.append((
                    "stale/\(source)/\(String(describing: binding))",
                    state(snapshot: ready, lastAttempt: .succeeded(at: readAt), source: source),
                    11 * 60
                ))

                let exhausted = snapshot(percent: "100", source: source, binding: binding)
                cases.append((
                    "exhausted/\(source)/\(String(describing: binding))",
                    state(snapshot: exhausted, lastAttempt: .succeeded(at: readAt), source: source),
                    60
                ))
            }
        }

        return cases.map { (label: $0.0, state: $0.1, afterSeconds: $0.2) }
    }
}

@Suite("Não exposição da credencial")
struct CredentialExposureTests {
    @Test("QB-APP-001 AC-28: o texto do indicador nunca ecoa string vinda da origem")
    func indicatorTextNeverEchoesOriginStrings() {
        for testCase in Sweep.everyState() {
            let surfaces = Sweep.surfaces(testCase.state, afterSeconds: testCase.afterSeconds)
            #expect(!surfaces.indicator.contains(canary), "vazou no indicador em \(testCase.label)")
        }
    }

    @Test("QB-APP-001 AC-28: o rótulo de acessibilidade nunca ecoa string vinda da origem")
    func accessibilityLabelNeverEchoesOriginStrings() {
        for testCase in Sweep.everyState() {
            let surfaces = Sweep.surfaces(testCase.state, afterSeconds: testCase.afterSeconds)
            #expect(!surfaces.accessibility.contains(canary), "vazou no rótulo em \(testCase.label)")
        }
    }

    @Test("QB-APP-001 AC-28: nenhuma linha do painel ecoa string vinda da origem")
    func noPanelLineEchoesOriginStrings() {
        for testCase in Sweep.everyState() {
            let surfaces = Sweep.surfaces(testCase.state, afterSeconds: testCase.afterSeconds)
            for line in Sweep.allStrings(of: surfaces.panel) {
                #expect(!line.contains(canary), "vazou no painel em \(testCase.label): \(line)")
            }
        }
    }

    @Test("QB-APP-001 AC-32: janela limitante não reconhecida é declarada como condição, sem citar a carga")
    func unrecognisedBindingWindowIsDeclaredWithoutThePayload() {
        var declared = 0

        for testCase in Sweep.everyState() where testCase.label.contains("unrecognized") {
            let surfaces = Sweep.surfaces(testCase.state, afterSeconds: testCase.afterSeconds)
            guard let selection = surfaces.panel.selection else { continue }

            #expect(!selection.contains(canary))
            #expect(selection.contains("não reconhece"))
            declared += 1
        }

        #expect(declared > 0, "o caso de janela não reconhecida não foi exercitado")
    }

    @Test("QB-APP-001 AC-32: o valor cru segue preservado no modelo, fora da interface")
    func rawValueRemainsAvailableInTheModel() {
        let snapshot = Sweep.snapshot(percent: "42", source: .primaryProbe, binding: .unrecognized(canary))

        #expect(snapshot.bindingWindow == .unrecognized(canary))
        #expect(WindowSelector.select(from: snapshot)
            == .chosenByApp(.fiveHour, reason: .originReportedUnknownValue(canary)))
    }

    @Test("QB-APP-001 AC-28: a ação de encerrar está presente nos seis estados, nos dois modos de fonte")
    func quitSurvivesTheWholeSweep() {
        for testCase in Sweep.everyState() {
            let surfaces = Sweep.surfaces(testCase.state, afterSeconds: testCase.afterSeconds)
            #expect(!surfaces.panel.quitTitle.isEmpty, "sem ação de encerrar em \(testCase.label)")
        }
    }

    @Test("QB-APP-001 REQ-14 e ADR-003: o estado de cota não carrega valor de credencial, apenas a indicação booleana")
    func quotaStateCarriesNoCredentialValue() {
        let state = Sweep.state(
            snapshot: Sweep.snapshot(percent: "42", source: .primaryProbe, binding: .window(.fiveHour)),
            lastAttempt: .succeeded(at: Sweep.readAt),
            source: .primaryProbe
        )

        let mirror = Mirror(reflecting: state)
        let credentialMembers = mirror.children.filter { ($0.label ?? "").lowercased().contains("credential") }

        #expect(credentialMembers.count == 1)
        #expect(credentialMembers.first?.label == "credentialPresent")
        #expect(credentialMembers.first?.value is Bool)
    }

    @Test("QB-APP-001 REQ-14: nenhuma superfície muda de conteúdo conforme a credencial exista ou não, além da situação declarada")
    func credentialPresenceOnlyChangesDeclaredLines() {
        let snapshot = Sweep.snapshot(percent: "33", source: .contingencyStatusLine, binding: nil)
        let withCredential = Sweep.state(
            snapshot: snapshot, credentialPresent: true,
            lastAttempt: .succeeded(at: Sweep.readAt), source: .contingencyStatusLine
        )
        let withoutCredential = Sweep.state(
            snapshot: snapshot, credentialPresent: false,
            lastAttempt: .succeeded(at: Sweep.readAt), source: .contingencyStatusLine
        )

        let a = Sweep.surfaces(withCredential, afterSeconds: 60)
        let b = Sweep.surfaces(withoutCredential, afterSeconds: 60)

        #expect(a.indicator == b.indicator)
        #expect(a.accessibility == b.accessibility)
        #expect(a.panel.credentialNotice == nil)
        #expect(b.panel.credentialNotice == PanelText.credentialAbsentInContingency)
    }
}
