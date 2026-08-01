# QuotaBar

Aplicativo nativo de macOS que mostra o consumo da sua cota do Claude Code
direto na **barra de menus** — sempre à vista, sem abrir nada.

## O problema

O limite de uso chega sem aviso. Quando você percebe, está no meio de uma tarefa
e a janela acabou. Descobrir quanto ainda resta exige parar o que está fazendo.

## A proposta

Um indicador permanente no canto superior da tela, com o percentual da janela
corrente e o horário do reset. Ao clicar, o detalhamento. Antes do limite, um
aviso.

## Estado

**Fundação.** O projeto está na etapa de definição: processo, decisões
arquiteturais e especificações. Ainda não há aplicativo instalável.

## Como este projeto é construído

QuotaBar é desenvolvido com **Spec-Driven Development**: toda mudança de
comportamento começa por uma especificação escrita, revisada e aprovada, da qual
derivam os critérios de aceite, os testes e só então o código.

- Método: [`docs/development/spec-driven-development.md`](docs/development/spec-driven-development.md)
- Decisões: [`docs/adr/`](docs/adr/)
- Especificações: [`specs/`](specs/)

## Como gerar e abrir o projeto

O arquivo `QuotaBar.xcodeproj` **não é versionado**: ele é gerado a partir do
`project.yml` pelo [XcodeGen](https://github.com/yonaskolb/XcodeGen), conforme a
[ADR-004](docs/adr/ADR-004-geracao-do-projeto-xcode.md). É preciso gerá-lo antes
de abrir o Xcode pela primeira vez, e novamente depois de qualquer mudança no
`project.yml`.

```sh
brew install xcodegen
xcodegen generate
open QuotaBar.xcodeproj
```

Configuração feita pela interface do Xcode é descartada na próxima geração —
toda mudança de projeto vai no `project.yml`.

A lógica de domínio vive no pacote local `Packages/QuotaBarCore`, sem dependência
de SwiftUI, e pode ser compilada e testada sem o Xcode:

```sh
swift build --package-path Packages/QuotaBarCore
swift test --package-path Packages/QuotaBarCore
```

Compilação do aplicativo em linha de comando:

```sh
xcodebuild -project QuotaBar.xcodeproj -scheme QuotaBar -configuration Release build
```

## Requisitos previstos

- macOS 14.0 ou superior
- Uma credencial de autenticação da API da Anthropic, guardada no Keychain do
  sistema

## Autoria

Renan Ravelli.
