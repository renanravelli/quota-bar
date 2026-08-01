import Testing

@testable import QuotaBarCore

@Suite("Rótulo de acessibilidade do indicador")
struct IndicatorAccessibilityLabelTests {
    private static let failureReasons = FailureReason.allCases

    private static func displayValue(_ window: QuotaWindow, _ percent: String) -> DisplayValue {
        let utilization = TestSnapshot.utilization(percent)!
        return DisplayValue(
            selection: .reportedByOrigin(window),
            utilization: utilization,
            band: ConsumptionBand(utilization: utilization)
        )
    }

    private static func statesOfEachKind(_ percent: String = "60") -> [IndicatorState] {
        let value = displayValue(.fiveHour, percent)
        return [
            .notConfigured,
            .loading,
            .failed(.communicationFailure),
            .stale(value),
            .exhausted(displayValue(.fiveHour, "100")),
            .ready(value),
        ]
    }

    @Test("AC-24: em ready o rótulo enuncia a janela e o percentual por extenso")
    func readyAnnouncesWindowAndPercent() {
        let label = IndicatorAccessibilityLabel.text(
            for: .ready(Self.displayValue(.sevenDay, "78")),
            source: .primaryProbe
        )

        #expect(label == "QuotaBar, janela semanal, 78 por cento consumidos")
    }

    @Test("AC-24: em stale o rótulo enuncia também que o dado está desatualizado")
    func staleAnnouncesOutdatedData() {
        let label = IndicatorAccessibilityLabel.text(
            for: .stale(Self.displayValue(.fiveHour, "78")),
            source: .primaryProbe
        )

        #expect(label == "QuotaBar, janela de 5 horas, 78 por cento consumidos, dado desatualizado")
    }

    @Test("AC-24: em notConfigured o rótulo enuncia a credencial não configurada")
    func notConfiguredAnnouncesMissingCredential() {
        let label = IndicatorAccessibilityLabel.text(for: .notConfigured, source: .primaryProbe)

        #expect(label == "QuotaBar, credencial não configurada")
    }

    @Test("AC-24: o rótulo não se limita a repetir o texto do indicador")
    func labelIsNotTheIndicatorText() {
        let situations: [IndicatorState] = [
            .ready(Self.displayValue(.sevenDay, "78")),
            .stale(Self.displayValue(.fiveHour, "78")),
            .notConfigured,
        ]

        for state in situations {
            let label = IndicatorAccessibilityLabel.text(for: state, source: .primaryProbe)
            let text = IndicatorTextFormatter.text(for: state)

            #expect(label != text)
            #expect(!label.isEmpty)
            #expect(!label.contains("%"), "rótulo '\(label)' usa sinal em vez de palavra")
            #expect(!label.contains("~"), "rótulo '\(label)' usa sinal em vez de palavra")
            #expect(!label.contains("5h"), "rótulo '\(label)' usa a abreviação da barra")
            #expect(!label.contains("7d"), "rótulo '\(label)' usa a abreviação da barra")
        }
    }

    @Test("AC-24: cada um dos seis estados tem rótulo próprio")
    func everyStateHasItsOwnLabel() {
        let labels = Self.statesOfEachKind().map {
            IndicatorAccessibilityLabel.text(for: $0, source: .primaryProbe)
        }

        #expect(Set(labels).count == 6)
        #expect(labels.allSatisfy { $0.hasPrefix("QuotaBar, ") })
    }

    @Test("AC-24 e AC-49: os sete motivos de falha são enunciados de forma distinta entre si e de notConfigured")
    func everyFailureReasonHasItsOwnPhrase() {
        let labels = Self.failureReasons.map {
            IndicatorAccessibilityLabel.text(for: .failed($0), source: .primaryProbe)
        }
        let notConfigured = IndicatorAccessibilityLabel.text(for: .notConfigured, source: .primaryProbe)
        let loading = IndicatorAccessibilityLabel.text(for: .loading, source: .primaryProbe)

        #expect(Self.failureReasons.count == 7)
        #expect(Set(labels).count == Self.failureReasons.count)
        #expect(!labels.contains(notConfigured))
        #expect(!labels.contains(loading))
    }

    @Test("AC-49: o rótulo de Claude Code não encontrado não fala em credencial")
    func claudeCodeNotFoundIsNotACredentialPhrase() {
        let label = IndicatorAccessibilityLabel.text(for: .failed(.claudeCodeNotFound), source: .primaryProbe)

        #expect(label == "QuotaBar, Claude Code não encontrado")
        #expect(!label.lowercased().contains("credencial"))
    }

    @Test("AC-24: os estados sem valor não anunciam janela nem percentual")
    func statesWithoutValueAnnounceNeitherWindowNorPercent() {
        var states: [IndicatorState] = [.notConfigured, .loading]
        states.append(contentsOf: Self.failureReasons.map { .failed($0) })

        for state in states {
            let label = IndicatorAccessibilityLabel.text(for: state, source: .primaryProbe)

            #expect(!label.contains("janela"), "rótulo '\(label)' anuncia janela sem valor exibível")
            #expect(!label.contains("por cento"), "rótulo '\(label)' anuncia percentual sem valor exibível")
        }
    }

    @Test("AC-24: em exhausted o rótulo enuncia o esgotamento com o percentual recortado em 100")
    func exhaustedAnnouncesDepletion() {
        let atLimit = IndicatorAccessibilityLabel.text(
            for: .exhausted(Self.displayValue(.fiveHour, "100")),
            source: .primaryProbe
        )
        let aboveLimit = IndicatorAccessibilityLabel.text(
            for: .exhausted(Self.displayValue(.fiveHour, "118")),
            source: .primaryProbe
        )
        let staleAboveLimit = IndicatorAccessibilityLabel.text(
            for: .stale(Self.displayValue(.sevenDay, "250")),
            source: .primaryProbe
        )

        #expect(atLimit == "QuotaBar, janela de 5 horas, 100 por cento consumidos, cota esgotada")
        #expect(aboveLimit == atLimit)
        #expect(staleAboveLimit == "QuotaBar, janela semanal, 100 por cento consumidos, dado desatualizado")
    }

    @Test("AC-24: as duas janelas são nomeadas por extenso e sem ambiguidade")
    func bothWindowsAreNamedInFull() {
        let fiveHour = IndicatorAccessibilityLabel.text(
            for: .ready(Self.displayValue(.fiveHour, "42")),
            source: .primaryProbe
        )
        let sevenDay = IndicatorAccessibilityLabel.text(
            for: .ready(Self.displayValue(.sevenDay, "42")),
            source: .primaryProbe
        )

        #expect(fiveHour == "QuotaBar, janela de 5 horas, 42 por cento consumidos")
        #expect(sevenDay == "QuotaBar, janela semanal, 42 por cento consumidos")
    }

    @Test("AC-24: o percentual é anunciado por palavra em toda a faixa de valores")
    func percentIsAnnouncedInWords() {
        for percent in ["0", "7", "42", "74", "75", "89", "90", "99"] {
            let label = IndicatorAccessibilityLabel.text(
                for: .ready(Self.displayValue(.fiveHour, percent)),
                source: .primaryProbe
            )

            #expect(label.contains("\(percent) por cento consumidos"), "rótulo '\(label)' não anuncia \(percent)")
        }
    }

    @Test("AC-24: o percentual anunciado acompanha o exibido, inclusive quando truncado")
    func announcedPercentMatchesTheDisplayedOne() {
        for percent in ["78.9", "50.4", "99.99", "118"] {
            let state = IndicatorState.ready(Self.displayValue(.fiveHour, percent))
            let label = IndicatorAccessibilityLabel.text(for: state, source: .primaryProbe)
            let displayed = IndicatorTextFormatter.text(for: state)
                .replacingOccurrences(of: "5h ", with: "")
                .replacingOccurrences(of: "%", with: "")

            #expect(label.contains("\(displayed) por cento consumidos"), "rótulo '\(label)' diverge de '\(displayed)'")
        }
    }

    @Test("AC-24: o modo de contingência é anunciado em todos os seis estados")
    func contingencyIsAnnouncedInEveryState() {
        for state in Self.statesOfEachKind() {
            let primary = IndicatorAccessibilityLabel.text(for: state, source: .primaryProbe)
            let contingency = IndicatorAccessibilityLabel.text(for: state, source: .contingencyStatusLine)

            #expect(!primary.contains("contingência"), "rótulo '\(primary)' anuncia contingência em fonte primária")
            #expect(contingency == primary + ", modo de contingência")
        }
    }

    @Test("AC-24: em contingência e obsoleto as duas condições são anunciadas")
    func staleUnderContingencyAnnouncesBothConditions() {
        let label = IndicatorAccessibilityLabel.text(
            for: .stale(Self.displayValue(.fiveHour, "33")),
            source: .contingencyStatusLine
        )

        #expect(label == "QuotaBar, janela de 5 horas, 33 por cento consumidos, dado desatualizado, modo de contingência")
    }
}
