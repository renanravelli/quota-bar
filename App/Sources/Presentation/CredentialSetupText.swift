import QuotaBarCore
import QuotaBarTransport

struct CredentialSetupMessage: Equatable {
    enum UserAction: Equatable {
        case generateNewCredential
        case installClaudeCode
        case waitForNetwork
        case tryAgain
        case nothingToDo
    }

    let text: String
    let action: UserAction
}

enum CredentialSetupText {
    static let command = "claude setup-token"
    static let title = "Credencial do QuotaBar"

    static let commandStep = "1. Rode este comando no Terminal:"

    static let steps = [
        "2. Cole aqui o valor que ele devolver.",
        "3. Salve: o QuotaBar verifica com uma leitura real antes de guardar."
    ]

    static let copyCommand = "Copiar o comando"
    static let fieldLabel = "Credencial gerada pelo comando"
    static let save = "Salvar"
    static let cancel = "Cancelar"
    static let replace = "Substituir"
    static let remove = "Remover"

    static let assist = "Conectar agora — o QuotaBar abre a autorização no navegador"
    static let send = "Enviar"

    static let assistNeedsClaudeCode =
        "A configuração automática depende do Claude Code, que não foi encontrado nesta máquina."

    static let codeFieldLabel = "Se o navegador exibir um código no formato código#estado, cole-o aqui"

    static let submitNeedsCode =
        "Enviar fica disponível assim que houver um código colado no campo acima."

    static let saveBusyWithAssistance =
        "Há uma configuração automática em curso. Cancele-a para salvar um valor colado à mão."

    static let saveNeedsClaudeCode =
        "Sem o Claude Code instalado não há leitura possível, e por isso não há como verificar uma credencial."

    static let cost =
        "Concluir a configuração custa uma requisição da própria cota — a leitura real que verifica a credencial. "
        + "A configuração automática não acrescenta nenhuma."

    static func waiting(at stage: AssistedSetupProgress) -> String {
        switch stage {
        case .launching:
            "Iniciando a configuração automática."
        case .waitingForApproval:
            "A autorização foi aberta no navegador. O QuotaBar aguarda a aprovação."
        }
    }

    static let configuredNotice =
        "Existe uma credencial configurada. O QuotaBar não a exibe nem a copia — só permite substituí-la ou removê-la."

    static let claudeCodeMissing =
        "O Claude Code não foi encontrado nesta máquina. Sem ele não há leitura possível, "
        + "e a credencial não pode ser verificada. Instale o Claude Code para continuar."

    static let malformedValue = CredentialSetupMessage(
        text: "Esperava-se a credencial de assinatura gerada por claude setup-token, que começa com sk-ant-oat01-. "
            + "Nada foi enviado e nada foi guardado.",
        action: .tryAgain
    )

    static let keychainWriteRefused = CredentialSetupMessage(
        text: "O Keychain recusou guardar a credencial. Isso não diz nada sobre a credencial em si; "
            + "libere o acesso ao Keychain e tente de novo.",
        action: .tryAgain
    )

    static let keychainReadRefused = CredentialSetupMessage(
        text: "O Keychain recusou informar se há credencial guardada. Isso não diz nada sobre a credencial em si; "
            + "libere o acesso ao Keychain e tente de novo.",
        action: .tryAgain
    )

    static let keychainRemoveRefused = CredentialSetupMessage(
        text: "O Keychain recusou remover a credencial. Ela continua configurada; "
            + "libere o acesso ao Keychain e tente de novo.",
        action: .tryAgain
    )

    static let removed = CredentialSetupMessage(
        text: "Credencial removida. O QuotaBar volta a declarar a pendência de credencial.",
        action: .nothingToDo
    )

    static let assistedCredentialRefused = CredentialSetupMessage(
        text: "A origem não aceitou a credencial que a configuração automática obteve. Nada foi guardado. "
            + "Dá para tentar a conexão de novo, ou usar a via manual aqui ao lado.",
        action: .tryAgain
    )

    static let credentialInCodeField = CredentialSetupMessage(
        text: "Esse valor tem a forma da credencial, e o lugar dele é o campo da credencial. "
            + "O campo do código espera o valor no formato código#estado que o navegador pode exibir. "
            + "Nada foi enviado.",
        action: .tryAgain
    )

    static let codeInCredentialField = CredentialSetupMessage(
        text: "Esse valor tem a forma do código que o navegador exibe, e o lugar dele é o campo do código, "
            + "oferecido enquanto a configuração automática espera. O campo da credencial espera o valor que "
            + "começa com sk-ant-oat01-. Nada foi enviado e nada foi guardado.",
        action: .tryAgain
    )

    static func message(for cause: AssistedSetupUnavailability) -> CredentialSetupMessage {
        let sentences = cause.mayMentionBrowserOrCode
            ? [summary(of: cause), browserCodeNote, wayForward(after: cause)]
            : [summary(of: cause), wayForward(after: cause)]

        return CredentialSetupMessage(
            text: sentences.joined(separator: " "),
            action: cause == .claudeCodeNotFound ? .installClaudeCode : .tryAgain
        )
    }

    static func message(for outcome: VerificationOutcome, obtainedByAssistance: Bool) -> CredentialSetupMessage {
        let refusedCredential = outcome == .credentialRejected || outcome == .credentialExpired
        guard obtainedByAssistance, refusedCredential else { return message(for: outcome) }

        return assistedCredentialRefused
    }

    private static let browserCodeNote =
        "O navegador pode ter exibido um código pedindo para colá-lo em um terminal: não há terminal nenhum "
        + "neste percurso, e o lugar dele era o campo desta tela, enquanto a espera durava."

    private static func summary(of cause: AssistedSetupUnavailability) -> String {
        switch cause {
        case .claudeCodeNotFound:
            "O Claude Code não foi encontrado, então a configuração automática não chegou a ser conduzida. "
                + "Nada foi guardado."
        case .launchFailed:
            "O QuotaBar não conseguiu conduzir a configuração automática. Nada foi guardado."
        case .silentBeforeAnySign:
            "A configuração automática não chegou a começar: não veio sinal de vida nenhum. Nada foi guardado."
        case .refusedByPolicy:
            "Uma política desta máquina ou desta conta barrou a configuração automática. Nada foi guardado."
        case .endedWithoutCredential:
            "A configuração automática terminou sem uma credencial que o QuotaBar pudesse usar. Nada foi guardado."
        case .approvalTimedOut:
            "O QuotaBar parou de esperar pela aprovação. Nada foi guardado, e não dá para afirmar que nada "
                + "tenha sido criado do outro lado."
        }
    }

    private static func wayForward(after cause: AssistedSetupUnavailability) -> String {
        cause == .claudeCodeNotFound
            ? "Instale o Claude Code para continuar."
            : "Dá para tentar de novo, ou seguir pela via manual apresentada aqui."
    }

    static func message(for outcome: VerificationOutcome) -> CredentialSetupMessage {
        switch outcome {
        case .success:
            CredentialSetupMessage(
                text: "Credencial verificada por uma leitura real e guardada no Keychain.",
                action: .nothingToDo
            )
        case .credentialRejected:
            CredentialSetupMessage(
                text: "A credencial não é mais aceita pela origem. Gere uma nova com claude setup-token.",
                action: .generateNewCredential
            )
        case .credentialExpired:
            CredentialSetupMessage(
                text: "A origem informou que a credencial expirou. Gere uma nova com claude setup-token.",
                action: .generateNewCredential
            )
        case .blockedByPolicy:
            CredentialSetupMessage(
                text: "A origem barrou este uso da credencial. Ela foi guardada, porque não é defeito do token "
                    + "nem da conta; enquanto o bloqueio durar, o QuotaBar não conseguirá ler o seu consumo.",
                action: .nothingToDo
            )
        case .communicationFailure:
            CredentialSetupMessage(
                text: "Não foi possível verificar agora. A credencial foi guardada, e o QuotaBar tentará "
                    + "por conta própria assim que a rede voltar.",
                action: .waitForNetwork
            )
        case .unexpectedResponse:
            CredentialSetupMessage(
                text: "A origem devolveu algo que o QuotaBar não soube interpretar. Nada foi guardado, "
                    + "e nem se confirmou nem se desmentiu a credencial. Vale tentar de novo.",
                action: .tryAgain
            )
        case .claudeCodeNotFound:
            CredentialSetupMessage(
                text: "O Claude Code não foi encontrado, então a verificação não chegou a acontecer "
                    + "e nada foi guardado. Instale o Claude Code para continuar.",
                action: .installClaudeCode
            )
        }
    }
}
