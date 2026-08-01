# QuotaBar

Quanto da sua cota do Claude Code já foi consumida, sempre à vista na barra de
menus do macOS.

Na barra fica a janela que limita primeiro e o percentual dela — `5h 42%`,
`7d 71%`. O símbolo muda de cor conforme o consumo sobe. Um clique abre o painel
com as duas janelas, a contagem regressiva até o reset e a idade da leitura que
está na tela.

> QuotaBar é um projeto independente, sem vínculo com a Anthropic e sem endosso
> dela. "Claude Code" e "Anthropic" aparecem aqui apenas para dizer o que o
> aplicativo mede.

## Estado

O aplicativo funciona. Compilado em `Release`, ele lê o consumo da sua conta
pela API da Anthropic, guarda a credencial no Keychain e vive na barra de menus
sem ícone no Dock.

Funciona hoje:

- indicador com janela limitante e percentual, e símbolo por faixa de consumo;
- painel com as duas janelas — percentual, barra segmentada, contagem regressiva
  e horário do reset;
- explicação de qual janela está na barra e por quê;
- idade da leitura, e aviso quando ela pode estar desatualizada;
- ritmo de releitura declarado em texto, com barra de progresso até a próxima;
- pendências de configuração ditas na cara: sem credencial, sem Claude Code;
- leitura preservada entre execuções, restaurada na abertura;
- sondagem suspensa quando a máquina dorme, e retomada ao acordar — o QuotaBar
  não impede o Mac de dormir;
- respeito a "Reduzir movimento" e a contraste aumentado, com rótulos de
  VoiceOver no indicador.

Não existe: notificação de alerta, tela de histórico e binário pronto para
baixar. Autenticação assistida e histórico estão em implementação — não conte
com eles ainda.

## Como ele mede, e o que a medida custa

O QuotaBar não tem uma fonte de leitura gratuita. Ele **faz uma requisição
mínima** para `api.anthropic.com/v1/messages` — um pedido de um único token — e
lê os cabeçalhos de limite de uso da resposta. É de lá que saem os percentuais,
os instantes de reset e a janela que limita primeiro.

**As leituras periódicas saem da mesma cota que ele mostra.** Isso é inerente ao
método, e não há como medir sem gastar. O que o aplicativo faz é gastar pouco e
com parcimônia: o intervalo base é de alguns minutos, alarga quando o consumo
não muda e ninguém está com o painel aberto, alarga mais depois de uma falha, e
tem piso. O painel sempre declara o intervalo corrente e por que ele é esse.

A requisição é autenticada com a credencial de assinatura do Claude Code e se
identifica com a versão do Claude Code instalado nesta máquina. Sem o Claude
Code instalado, não há leitura.

## Requisitos

- macOS 14.0 ou superior, em Mac com Apple Silicon (a build é só `arm64`).
- **Claude Code instalado** — é dele que sai a credencial, e sem ele o QuotaBar
  não lê nada.
- Para construir: Xcode com toolchain Swift 6, e
  [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## Instalação: só a partir do fonte

Não há build assinada com Developer ID, não há notarização e não há release para
baixar. Quem quiser usar o QuotaBar hoje constrói na própria máquina — e o
aplicativo resultante é assinado ad-hoc, válido para você mesmo e não para
distribuir.

```sh
git clone https://github.com/renanravelli/quota-bar.git
cd quota-bar
brew install xcodegen
xcodegen generate
xcodebuild -project QuotaBar.xcodeproj -scheme QuotaBar -configuration Release -derivedDataPath DerivedData build
open DerivedData/Build/Products/Release/QuotaBar.app
```

O produto fica em `DerivedData/Build/Products/Release/QuotaBar.app`; copie-o
para `/Applications` se quiser mantê-lo.

`QuotaBar.xcodeproj` **não é versionado**: é gerado pelo XcodeGen a partir do
`project.yml`. Gere-o de novo depois de qualquer mudança nesse arquivo — e saiba
que ajuste feito pela interface do Xcode é descartado na geração seguinte.

## Configurar a credencial

1. Gere a credencial de assinatura no Terminal:

   ```sh
   claude setup-token
   ```

2. Clique no indicador na barra de menus e escolha **Configurar a credencial**.
3. Cole o valor e salve.

Antes de guardar, o QuotaBar **verifica a credencial com uma leitura real** —
essa verificação também consome cota. Uma vez guardada, ela fica no Keychain do
sistema; o aplicativo não a exibe nem a copia de volta, só permite substituir ou
remover.

## A build `Debug` mostra números falsos

Isto é o que mais confunde quem clona o repositório: **`Debug` não fala com a
Anthropic**. Ela exclui o provedor real da compilação e alimenta a interface com
dados de teste que giram sozinhos, para que os estados possam ser vistos sem
gastar cota. O painel diz isso em destaque quando está nesse modo.

Rodar pelo Xcode usa `Debug`. Se você quer ver o seu consumo de verdade, precisa
ser `Release`.

## Desenvolvimento

A lógica de cota — janelas, faixas de consumo, escolha da janela limitante,
cadência, envelhecimento da leitura — vive no pacote local
`Packages/QuotaBarCore`, sem dependência de SwiftUI. Ela compila e é testada sem
Xcode e sem interface:

```sh
swift test --package-path Packages/QuotaBarCore
```

Os testes da camada de apresentação precisam do projeto gerado:

```sh
xcodebuild -project QuotaBar.xcodeproj -scheme QuotaBar test
```

Organização: `Packages/QuotaBarCore` (domínio puro), `QuotaBarTransport`
(Keychain, rede e integração com o sistema), `App/Sources` (SwiftUI e
`MenuBarExtra`).

Se você for iterar em `Debug` mexendo na credencial, gere antes uma identidade
de assinatura estável — a assinatura ad-hoc muda a cada compilação e invalida a
autorização do item no Keychain. O script pede a senha de login **duas vezes**,
em passos que não podem ser automatizados:

```sh
Scripts/create-dev-signing-identity.sh
export QUOTABAR_CODE_SIGN_IDENTITY="QuotaBar Development"
```

Toda build passa por um portão que reprova o produto se os direitos assinados, a
arquitetura ou o conjunto de arte não forem exatamente os esperados
(`Scripts/verify-signed-product.sh`).

## Privacidade

- A credencial fica **apenas no Keychain**. Não vai para `UserDefaults`, nem
  para arquivo de configuração, nem para variável de ambiente — e o tipo que a
  carrega se redige a si mesmo, para não vazar em log ou em depuração.
- O único destino de rede do aplicativo é `api.anthropic.com`.
- A última leitura é guardada em
  `~/Library/Application Support/QuotaBar/last-reading.json`, para que o painel
  tenha o que mostrar ao abrir. Ela contém percentuais e instantes — nunca a
  credencial.

## Autoria

Renan Ravelli.
