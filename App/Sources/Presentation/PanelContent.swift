import Foundation
import QuotaBarCore

struct WindowRow: Equatable {
    let name: String
    let utilization: String?
    let litSegments: Int
    let tint: QuotaBarCore.RGBColor?
    let countdown: String?
    let reset: String?
    let absences: [String]
}

enum CadenceMark: Equatable {
    case none
    case idleDashes
    case failureRing
    case deferralDashes

    static func mark(for nature: Cadence.Nature) -> CadenceMark {
        switch nature {
        case .base: .none
        case .idle: .idleDashes
        case .widenedByFailure: .failureRing
        case .deferredBySystem: .deferralDashes
        }
    }
}

struct CadenceBar: Equatable {
    let progress: Double
    let nature: Cadence.Nature

    var mark: CadenceMark {
        CadenceMark.mark(for: nature)
    }
}

struct PanelContent: Equatable {
    let fiveHour: WindowRow
    let sevenDay: WindowRow
    let selection: String?
    let situation: String
    let cadence: String?
    let cadenceBar: CadenceBar?
    let source: String?
    let contingencyLosses: [String]
    let credentialNotice: String?
    let sourceChangeNotice: String?
    let fixtureNotice: String?
    let pendencies: [String]
    let mascot: MascotExpression
    let configureCredentialTitle: String?
    let quitTitle: String

    var actionTitles: [String] {
        [configureCredentialTitle, quitTitle].compactMap { $0 }
    }
}

enum PanelText {
    static let fiveHourName = "Janela de cinco horas"
    static let sevenDayName = "Janela semanal"
    static let quit = "Encerrar o QuotaBar"
    static let configureCredential = "Configurar a credencial"

    static let credentialPending =
        "Pendência de configuração: configure a credencial para o QuotaBar ler o seu consumo."
    static let claudeCodePending =
        "Pendência de configuração: instale o Claude Code — sem ele nenhuma leitura é possível."

    static func pendency(_ pendency: ConfigurationPendency) -> String {
        switch pendency {
        case .credential: credentialPending
        case .claudeCode: claudeCodePending
        }
    }

    static func reason(_ reason: FailureReason) -> String {
        switch reason {
        case .credentialRejected:
            "A origem recusou a credencial."
        case .credentialExpired:
            "A credencial expirou. É preciso gerar uma nova."
        case .credentialUnreadable:
            "Não foi possível ler a credencial."
        case .blockedByPolicy:
            "A origem bloqueou este uso da credencial. Não é defeito do token nem da conta."
        case .claudeCodeNotFound:
            "O Claude Code não foi encontrado. Instale-o para que a leitura seja possível."
        case .communicationFailure:
            "Não foi possível falar com a origem."
        case .unexpectedResponse:
            "A origem devolveu uma resposta inesperada."
        }
    }

    static func sourceName(_ source: QuotaSource) -> String {
        switch source {
        case .primaryProbe: "Fonte: leitura da API da Anthropic"
        case .contingencyStatusLine: "Fonte: status line do Claude Code (contingência)"
        }
    }

    static let contingencyLosses = [
        "Não informa qual janela limita primeiro.",
        "Enxerga apenas o consumo desta máquina.",
        "Só se atualiza com o Claude Code em execução."
    ]

    static let fixtureFed =
        "Build de desenvolvimento: os números vêm de dados de teste, não da sua conta."

    static let credentialAbsentInContingency =
        "Não há credencial configurada. Sem ela, não há retorno à fonte primária."

    static func sourceChanged(to source: QuotaSource) -> String {
        switch source {
        case .contingencyStatusLine: "A fonte mudou para a contingência local."
        case .primaryProbe: "A fonte voltou para a leitura da API."
        }
    }

    static func cadenceLine(_ cadence: Cadence) -> String {
        let interval = intervalPhrase(cadence.interval)

        return switch cadence.nature {
        case .base: "Atualizando \(interval) — ritmo base."
        case .idle: "Atualizando \(interval) — reduzido por ociosidade."
        case .widenedByFailure: "Atualizando \(interval) — ampliado por falha."
        case .deferredBySystem: "Atualização adiada pelo sistema — o intervalo pretendido é \(interval)."
        }
    }

    private static func intervalPhrase(_ interval: Duration) -> String {
        let minutes = interval.components.seconds / 60
        let seconds = interval.components.seconds % 60

        return minutes > 0 && seconds == 0
            ? "a cada \(minutes) \(minutes == 1 ? "minuto" : "minutos")"
            : "a cada \(interval.components.seconds) segundos"
    }
}

enum PanelContentBuilder {
    static func build(
        state: QuotaState?,
        indicator: IndicatorState,
        at now: Date,
        deferralLatch: inout DeferralLatch,
        previouslySeenSource: QuotaSource? = nil,
        fixtureFed: Bool = false,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> PanelContent {
        let snapshot = state?.snapshot
        let formatter = TimeFormatter(locale: locale, timeZone: timeZone)
        let cadence = state?.cadence(at: now, latch: &deferralLatch)

        return PanelContent(
            fiveHour: row(name: PanelText.fiveHourName, reading: snapshot?.fiveHour, now: now, formatter: formatter),
            sevenDay: row(name: PanelText.sevenDayName, reading: snapshot?.sevenDay, now: now, formatter: formatter),
            selection: selectionLine(for: indicator),
            situation: situationLine(for: indicator, state: state, now: now, formatter: formatter),
            cadence: cadence.map(PanelText.cadenceLine),
            cadenceBar: cadenceBar(cadence, readAt: snapshot?.readAt, now: now),
            source: state?.source.map(PanelText.sourceName),
            contingencyLosses: state?.source == .contingencyStatusLine ? PanelText.contingencyLosses : [],
            credentialNotice: credentialNotice(for: state),
            sourceChangeNotice: sourceChangeNotice(for: state, previouslySeenSource: previouslySeenSource),
            fixtureNotice: fixtureFed ? PanelText.fixtureFed : nil,
            pendencies: pendencies(of: state),
            mascot: MascotResolver.expression(for: indicator),
            configureCredentialTitle: credentialIsPending(in: state) ? PanelText.configureCredential : nil,
            quitTitle: PanelText.quit
        )
    }

    private static func pendencies(of state: QuotaState?) -> [String] {
        (state?.pendencies ?? []).map(PanelText.pendency)
    }

    private static func credentialIsPending(in state: QuotaState?) -> Bool {
        state?.pendencies.contains(.credential) == true
    }

    private static func row(
        name: String,
        reading: WindowReading?,
        now: Date,
        formatter: TimeFormatter
    ) -> WindowRow {
        guard let reading else {
            return WindowRow(
                name: name,
                utilization: nil,
                litSegments: 0,
                tint: nil,
                countdown: nil,
                reset: nil,
                absences: ["Ainda não há leitura desta janela."]
            )
        }

        var absences: [String] = []
        if reading.utilization == nil {
            absences.append("Percentual não disponível: a origem não o forneceu.")
        }
        if reading.resetsAt == nil {
            absences.append("Instante de reset não disponível: a origem não o forneceu.")
        }

        return WindowRow(
            name: name,
            utilization: reading.utilization.map { "\($0.displayablePercent)%" },
            litSegments: reading.utilization.map(Meter.litSegments) ?? 0,
            tint: reading.utilization.map(ConsumptionGradient.color),
            countdown: countdown(until: reading.resetsAt, now: now),
            reset: reading.resetsAt.map(formatter.time(_:)),
            absences: absences
        )
    }

    private static func countdown(until resetsAt: Date?, now: Date) -> String? {
        guard let resetsAt else { return nil }
        let remaining = Duration.seconds(max(0, resetsAt.timeIntervalSince(now)))
        return CountdownText.text(remaining: remaining, format: CountdownPolicy.format(remaining: remaining))
    }

    private static func cadenceBar(_ cadence: Cadence?, readAt: Date?, now: Date) -> CadenceBar? {
        guard let cadence, let readAt else { return nil }

        let interval = Double(cadence.interval.components.seconds)
        guard interval > 0 else { return nil }

        let elapsed = max(0, now.timeIntervalSince(readAt))
        return CadenceBar(progress: min(elapsed / interval, 1), nature: cadence.nature)
    }

    private static func selectionLine(for indicator: IndicatorState) -> String? {
        guard let selection = displayValue(of: indicator)?.selection else { return nil }
        let name = selection.window == .fiveHour ? PanelText.fiveHourName : PanelText.sevenDayName

        switch selection {
        case .reportedByOrigin:
            return "Na barra: \(name), apontada pela origem como a que limita primeiro."
        case let .chosenByApp(_, reason):
            return "Na barra: \(name), escolhida pelo QuotaBar — \(text(for: reason))"
        }
    }

    private static func text(for reason: SelectionReason) -> String {
        switch reason {
        case .originDidNotReport:
            "a origem não informou a janela limitante."
        case .originReportedUnknownValue:
            "a origem informou uma janela que este aplicativo não reconhece."
        case let .originReportedWindowWithoutUtilization(window):
            "a origem apontou \(window == .fiveHour ? PanelText.fiveHourName : PanelText.sevenDayName), que está sem percentual."
        case .onlyOneWindowAvailable:
            "é a única janela com percentual disponível."
        }
    }

    private static func situationLine(
        for indicator: IndicatorState,
        state: QuotaState?,
        now: Date,
        formatter: TimeFormatter
    ) -> String {
        switch indicator {
        case .notConfigured:
            return "Credencial não configurada."
        case .loading:
            return "Primeira leitura em andamento."
        case let .failed(reason):
            return PanelText.reason(reason)
        case .ready, .exhausted:
            return "Atualizado \(age(state: state, now: now))."
        case .stale:
            return "Dado possivelmente desatualizado — atualizado \(age(state: state, now: now))."
        }
    }

    private static func age(state: QuotaState?, now: Date) -> String {
        guard let readAt = state?.snapshot?.readAt else { return "em instante desconhecido" }
        return AgeDisplay.phrase(for: StalenessPolicy.age(ofReadingAt: readAt, now: now))
    }

    private static func credentialNotice(for state: QuotaState?) -> String? {
        guard let state, !state.credentialPresent, state.source == .contingencyStatusLine else { return nil }
        return PanelText.credentialAbsentInContingency
    }

    private static func sourceChangeNotice(
        for state: QuotaState?,
        previouslySeenSource: QuotaSource?
    ) -> String? {
        guard let state, let currentSource = state.source, let previouslySeenSource,
              previouslySeenSource != currentSource else { return nil }
        return PanelText.sourceChanged(to: currentSource)
    }

    private static func displayValue(of indicator: IndicatorState) -> DisplayValue? {
        switch indicator {
        case let .ready(value), let .stale(value), let .exhausted(value): value
        case .notConfigured, .loading, .failed: nil
        }
    }
}

struct TimeFormatter {
    let locale: Locale
    let timeZone: TimeZone

    func time(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone)
        )
    }

}
