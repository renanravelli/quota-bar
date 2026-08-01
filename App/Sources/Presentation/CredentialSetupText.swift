import QuotaBarCore

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
