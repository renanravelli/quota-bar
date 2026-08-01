import Foundation
import Testing

@testable import QuotaBarCore

@Suite("Seleção da janela exibida")
struct WindowSelectorTests {
    @Test("AC-29: a barra segue a janela limitante informada pela origem")
    func followsWindowReportedByOrigin() {
        let snapshot = TestSnapshot.make(
            fiveHourPercent: "20",
            sevenDayPercent: "92",
            bindingWindow: .window(.sevenDay)
        )

        let selection = WindowSelector.select(from: snapshot)

        #expect(selection == .reportedByOrigin(.sevenDay))
        #expect(selection?.window == .sevenDay)
    }

    @Test("AC-30: a troca da janela limitante troca a seleção inteira")
    func followsOriginWhenBindingWindowChanges() {
        let before = TestSnapshot.make(fiveHourPercent: "78", sevenDayPercent: "44", bindingWindow: .window(.fiveHour))
        let after = TestSnapshot.make(fiveHourPercent: "78", sevenDayPercent: "44", bindingWindow: .window(.sevenDay))

        #expect(WindowSelector.select(from: before)?.window == .fiveHour)
        #expect(WindowSelector.select(from: after)?.window == .sevenDay)
    }

    @Test("AC-31: janela limitante ausente recai sobre o maior consumo, com procedência do app")
    func fallsBackToHighestConsumptionWhenOriginIsSilent() {
        let snapshot = TestSnapshot.make(
            fiveHourPercent: "31",
            sevenDayPercent: "67",
            bindingWindow: nil
        )

        let selection = WindowSelector.select(from: snapshot)

        #expect(selection == .chosenByApp(.sevenDay, reason: .originDidNotReport))
    }

    @Test("AC-32: janela limitante apontando para janela sem percentual usa a regra de contorno")
    func fallsBackWhenReportedWindowHasNoUtilization() {
        let snapshot = TestSnapshot.make(
            fiveHourPercent: nil,
            sevenDayPercent: "70",
            bindingWindow: .window(.fiveHour)
        )

        let selection = WindowSelector.select(from: snapshot)

        #expect(selection == .chosenByApp(.sevenDay, reason: .originReportedWindowWithoutUtilization(.fiveHour)))
    }

    @Test("AC-33: a comparação usa o valor antes do truncamento")
    func comparesBeforeTruncation() {
        let snapshot = TestSnapshot.make(
            fiveHourPercent: "50.4",
            sevenDayPercent: "50.6",
            bindingWindow: nil
        )

        let selection = WindowSelector.select(from: snapshot)

        #expect(selection?.window == .sevenDay)
        #expect(snapshot.fiveHour.utilization?.truncatedPercent == 50)
        #expect(snapshot.sevenDay.utilization?.truncatedPercent == 50)
    }

    @Test("AC-33: só a igualdade exata é empate, e o desempate é a janela de cinco horas")
    func breaksExactTiesTowardsFiveHourWindow() {
        let snapshot = TestSnapshot.make(
            fiveHourPercent: "50.0",
            sevenDayPercent: "50.0",
            bindingWindow: nil
        )

        #expect(WindowSelector.select(from: snapshot)?.window == .fiveHour)
    }

    @Test("AC-33: com uma única janela disponível, é ela a exibida")
    func selectsTheOnlyWindowWithUtilization() {
        let onlySevenDay = TestSnapshot.make(fiveHourPercent: nil, sevenDayPercent: "67", bindingWindow: nil)
        let onlyFiveHour = TestSnapshot.make(fiveHourPercent: "12", sevenDayPercent: nil, bindingWindow: nil)

        #expect(WindowSelector.select(from: onlySevenDay) == .chosenByApp(.sevenDay, reason: .onlyOneWindowAvailable))
        #expect(WindowSelector.select(from: onlyFiveHour) == .chosenByApp(.fiveHour, reason: .onlyOneWindowAvailable))
    }

    @Test("AC-33: leitura sem nenhuma janela com percentual não é construível")
    func readingWithoutAnyUtilizationIsNotConstructible() {
        let snapshot = TestSnapshot.build(fiveHourPercent: nil, sevenDayPercent: nil, bindingWindow: nil)

        #expect(snapshot == nil)
    }

    @Test("AC-32: valor de janela limitante não reconhecido é distinto de ausente")
    func unrecognisedBindingWindowIsDistinctFromAbsent() {
        let unrecognised = TestSnapshot.make(
            fiveHourPercent: "31",
            sevenDayPercent: "67",
            bindingWindow: .unrecognized("seven_day_opus")
        )
        let absent = TestSnapshot.make(
            fiveHourPercent: "31",
            sevenDayPercent: "67",
            bindingWindow: nil
        )

        let fromUnrecognised = WindowSelector.select(from: unrecognised)
        let fromAbsent = WindowSelector.select(from: absent)

        #expect(fromUnrecognised == .chosenByApp(.sevenDay, reason: .originReportedUnknownValue("seven_day_opus")))
        #expect(fromAbsent == .chosenByApp(.sevenDay, reason: .originDidNotReport))
        #expect(fromUnrecognised != fromAbsent)
        #expect(fromUnrecognised?.window == fromAbsent?.window)
    }

    @Test("AC-32: valor não reconhecido não descarta a leitura nem muda a janela escolhida")
    func unrecognisedBindingWindowStillUsesHighestConsumption() {
        let snapshot = TestSnapshot.make(
            fiveHourPercent: "92",
            sevenDayPercent: "20",
            bindingWindow: .unrecognized("five_hour_opus")
        )

        #expect(WindowSelector.select(from: snapshot)?.window == .fiveHour)
    }

    @Test("AC-29: a janela informada só vale quando tem percentual disponível")
    func honoursReportedWindowOnlyWhenItHasUtilization() {
        let reported = TestSnapshot.make(fiveHourPercent: "20", sevenDayPercent: "92", bindingWindow: .window(.fiveHour))

        #expect(WindowSelector.select(from: reported) == .reportedByOrigin(.fiveHour))
    }

    @Test("AC-31: a escolha do app nunca é gravada de volta no campo da origem")
    func appChoiceNeverWritesBackToOriginField() {
        let snapshot = TestSnapshot.make(fiveHourPercent: "31", sevenDayPercent: "67", bindingWindow: nil)

        let selection = WindowSelector.select(from: snapshot)

        #expect(selection?.window == .sevenDay)
        #expect(snapshot.bindingWindow == nil)
    }
}
