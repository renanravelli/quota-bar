import Foundation
import Testing

@testable import QuotaBarCore

@Suite("Formatador do texto do indicador")
struct IndicatorTextFormatterTests {
    private static func displayValue(_ window: QuotaWindow, _ percent: String) -> DisplayValue {
        let utilization = TestSnapshot.utilization(percent)!
        return DisplayValue(
            selection: .reportedByOrigin(window),
            utilization: utilization,
            band: ConsumptionBand(utilization: utilization)
        )
    }

    @Test("AC-3: janela de cinco horas com 78,9% é exibida como 5h 78%")
    func readyTextForFiveHourWindow() {
        let text = IndicatorTextFormatter.text(for: .ready(Self.displayValue(.fiveHour, "78.9")))

        #expect(text == "5h 78%")
    }

    @Test("AC-34: o rótulo da janela semanal é 7d")
    func readyTextForSevenDayWindow() {
        #expect(IndicatorTextFormatter.text(for: .ready(Self.displayValue(.sevenDay, "41"))) == "7d 41%")
    }

    @Test("AC-6: obsoleto recebe o sinal ~ imediatamente antes do percentual")
    func staleTextCarriesTilde() {
        #expect(IndicatorTextFormatter.text(for: .stale(Self.displayValue(.fiveHour, "42"))) == "5h ~42%")
        #expect(IndicatorTextFormatter.text(for: .stale(Self.displayValue(.sevenDay, "78"))) == "7d ~78%")
    }

    @Test("AC-15: esgotado é exibido com o rótulo e 100%")
    func exhaustedText() {
        #expect(IndicatorTextFormatter.text(for: .exhausted(Self.displayValue(.fiveHour, "100"))) == "5h 100%")
    }

    @Test("AC-16: percentual acima de 100 é recortado para 100% na exibição")
    func overageIsClippedToOneHundred() {
        #expect(IndicatorTextFormatter.text(for: .exhausted(Self.displayValue(.fiveHour, "118"))) == "5h 100%")
        #expect(IndicatorTextFormatter.text(for: .exhausted(Self.displayValue(.sevenDay, "250"))) == "7d 100%")
        #expect(IndicatorTextFormatter.text(for: .stale(Self.displayValue(.fiveHour, "118"))) == "5h ~100%")
    }

    @Test("AC-7 e AC-8: os estados sem valor não têm texto")
    func statesWithoutValueHaveNoText() {
        #expect(IndicatorTextFormatter.text(for: .notConfigured).isEmpty)
        #expect(IndicatorTextFormatter.text(for: .loading).isEmpty)
        #expect(IndicatorTextFormatter.text(for: .failed(.communicationFailure)).isEmpty)
        #expect(IndicatorTextFormatter.text(for: .failed(.credentialExpired)).isEmpty)
    }

    @Test("AC-34: o texto começa sempre pelo rótulo da janela e nunca mostra percentual sem rótulo")
    func textAlwaysStartsWithWindowLabel() {
        for window in [QuotaWindow.fiveHour, .sevenDay] {
            let label = window == .fiveHour ? "5h" : "7d"
            for percent in ["0", "7", "42", "99", "100", "118"] {
                let value = Self.displayValue(window, percent)
                for state in [IndicatorState.ready(value), .stale(value), .exhausted(value)] {
                    let text = IndicatorTextFormatter.text(for: state)
                    #expect(text.hasPrefix(label), "texto '\(text)' não começa por '\(label)'")
                    #expect(text.hasSuffix("%"))
                }
            }
        }
    }

    @Test("AC-34: nenhuma combinação de estado excede nove caracteres")
    func noCombinationExceedsMaximumLength() {
        var widest = ""

        for window in [QuotaWindow.fiveHour, .sevenDay] {
            for basisPoints in stride(from: 0, through: 30_000, by: 1) {
                guard let utilization = Utilization(basisPoints: basisPoints) else {
                    Issue.record("basis points \(basisPoints) deveria ser representável")
                    continue
                }
                let value = DisplayValue(
                    selection: .chosenByApp(window, reason: .originDidNotReport),
                    utilization: utilization,
                    band: ConsumptionBand(utilization: utilization)
                )

                for state in [IndicatorState.ready(value), .stale(value), .exhausted(value)] {
                    let text = IndicatorTextFormatter.text(for: state)
                    #expect(text.count <= IndicatorTextFormatter.maxLength, "texto '\(text)' excede o teto")
                    if text.count > widest.count { widest = text }
                }
            }
        }

        #expect(IndicatorTextFormatter.maxLength == 9)
        #expect(widest.count == 8)
    }

    @Test("AC-34: o pior caso corrente é 5h ~100%, com oito caracteres")
    func worstCaseLeavesOneCharacterOfSlack() {
        let text = IndicatorTextFormatter.text(for: .stale(Self.displayValue(.fiveHour, "100")))

        #expect(text == "5h ~100%")
        #expect(text.count == 8)
        #expect(IndicatorTextFormatter.maxLength - text.count == 1)
    }

    @Test("AC-30: rótulo e percentual mudam juntos, nunca cruzados")
    func labelAndPercentChangeTogether() {
        let before = IndicatorTextFormatter.text(for: .ready(Self.displayValue(.fiveHour, "78")))
        let after = IndicatorTextFormatter.text(for: .ready(Self.displayValue(.sevenDay, "44")))

        #expect(before == "5h 78%")
        #expect(after == "7d 44%")
    }
}
