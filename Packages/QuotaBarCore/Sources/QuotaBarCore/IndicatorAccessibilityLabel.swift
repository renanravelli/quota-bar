public enum IndicatorAccessibilityLabel {
    private static let appName = "QuotaBar"

    public static func text(for state: IndicatorState, source: QuotaSource) -> String {
        ([appName] + phrases(for: state) + phrases(for: source)).joined(separator: ", ")
    }

    private static func phrases(for state: IndicatorState) -> [String] {
        switch state {
        case .notConfigured: ["credencial não configurada"]
        case .loading: ["primeira leitura em andamento"]
        case let .failed(reason): [phrase(for: reason)]
        case let .ready(value): phrases(for: value)
        case let .exhausted(value): phrases(for: value) + ["cota esgotada"]
        case let .stale(value): phrases(for: value) + ["dado desatualizado"]
        }
    }

    private static func phrases(for value: DisplayValue) -> [String] {
        [
            name(for: value.selection.window),
            "\(value.utilization.displayablePercent) por cento consumidos",
        ]
    }

    private static func phrases(for source: QuotaSource) -> [String] {
        switch source {
        case .primaryProbe: []
        case .contingencyStatusLine: ["modo de contingência"]
        }
    }

    private static func name(for window: QuotaWindow) -> String {
        switch window {
        case .fiveHour: "janela de 5 horas"
        case .sevenDay: "janela semanal"
        }
    }

    private static func phrase(for reason: FailureReason) -> String {
        switch reason {
        case .credentialRejected: "credencial rejeitada"
        case .credentialExpired: "credencial expirada"
        case .credentialUnreadable: "não foi possível ler a credencial"
        case .blockedByPolicy: "uso bloqueado por política"
        case .claudeCodeNotFound: "Claude Code não encontrado"
        case .communicationFailure: "falha de comunicação"
        case .unexpectedResponse: "resposta inesperada"
        }
    }
}
