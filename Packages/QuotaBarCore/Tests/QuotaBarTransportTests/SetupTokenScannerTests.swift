import Testing

@testable import QuotaBarTransport

extension SetupTokenScanner {
    mutating func consume(_ bytes: [UInt8]) -> Outcome {
        bytes.withUnsafeBytes { consume($0) }
    }

    mutating func consume(_ text: String) -> Outcome {
        consume(Array(text.utf8))
    }

    static func outcome(of stream: [UInt8], cutAt boundaries: [Int]) -> Outcome {
        var scanner = SetupTokenScanner()
        var last = Outcome.pending
        var start = 0

        for boundary in boundaries + [stream.count] {
            last = scanner.consume(Array(stream[start..<boundary]))
            start = boundary
        }

        return last
    }
}

enum TerminalFrame {
    static let token = "sk-ant-oat01-" + String(repeating: "aB9_-=", count: 16)

    static let redrawn =
        "\u{1B}[2J\u{1B}[H\u{1B}[?25l"
        + "\u{1B}[38;5;214mQuotaBar\u{1B}[0m\r\n"
        + "\u{1B}[2K\u{1B}[1;1HYour OAuth token (valid for 1 year):\r\n"
        + "\u{1B}[33m" + token + "\u{1B}[39m\r\n"
        + "\u{1B}]0;done\u{07}\u{1B}[?25h"

    static var bytes: [UInt8] { Array(redrawn.utf8) }
}

@Suite("Extração do token do fluxo de saída do terminal", .timeLimit(.minutes(1)))
struct SetupTokenScannerTests {
    @Test("o token é casado pela forma no meio de um quadro cheio de sequências de escape")
    func theTokenIsMatchedByShapeInsideAnEscapedFrame() {
        var scanner = SetupTokenScanner()

        #expect(scanner.consume(TerminalFrame.bytes) == .found(TerminalFrame.token))
    }

    @Test("renomear o rótulo em inglês não muda o casamento, porque o rótulo não participa dele")
    func renamingTheEnglishLabelDoesNotChangeTheMatch() {
        var scanner = SetupTokenScanner()
        let relabelled = TerminalFrame.redrawn.replacingOccurrences(
            of: "Your OAuth token (valid for 1 year):",
            with: "Seu token, renomeado pela origem:"
        )

        #expect(scanner.consume(relabelled) == .found(TerminalFrame.token))
    }

    @Test("o mesmo fluxo cortado em qualquer posição produz o mesmo casamento")
    func theSameStreamCutAnywhereProducesTheSameMatch() {
        let stream = TerminalFrame.bytes

        for boundary in 0...stream.count {
            #expect(
                SetupTokenScanner.outcome(of: stream, cutAt: [boundary]) == .found(TerminalFrame.token),
                "o corte em \(boundary) mudou o casamento"
            )
        }
    }

    @Test("o mesmo fluxo entregue byte a byte produz o mesmo casamento")
    func theSameStreamDeliveredByteByByteProducesTheSameMatch() {
        let stream = TerminalFrame.bytes

        #expect(SetupTokenScanner.outcome(of: stream, cutAt: Array(0...stream.count)) == .found(TerminalFrame.token))
    }

    @Test("token partido em duas linhas pelo layout não é remontado")
    func aTokenSplitAcrossTwoLinesIsNotReassembled() {
        var scanner = SetupTokenScanner()
        let split = "\u{1B}[33msk-ant-oat01-aB9\r\n" + String(repeating: "aB9_-=", count: 16) + "\u{1B}[39m\r\n"

        let outcome = scanner.consume(split)

        #expect(outcome != .found(TerminalFrame.token))
        #expect(outcome == .pending)
    }

    @Test("corpo interrompido por quebra de linha nunca vira o token inteiro por concatenação")
    func aBodyInterruptedByALineBreakIsNeverConcatenatedIntoTheWholeToken() {
        var scanner = SetupTokenScanner()
        let head = "sk-ant-oat01-" + String(repeating: "aB9_-=", count: 8)
        let tail = String(repeating: "aB9_-=", count: 8)

        let outcome = scanner.consume(head + "\r\n" + tail + "\r\n")

        #expect(outcome != .found(TerminalFrame.token))
        #expect(outcome != .found(head + tail))
        #expect(outcome == .found(head))
    }

    @Test("fluxo sem token até o limite de varredura devolve exaustão, e nada depois dele casa")
    func aStreamWithoutATokenIsExhaustedAtTheScanLimit() {
        var scanner = SetupTokenScanner()
        let noise = [UInt8](repeating: 0x78, count: 1 << 16)

        for _ in 0..<15 {
            #expect(scanner.consume(noise) == .pending)
        }

        #expect(scanner.consume(noise) == .exhausted)
        #expect(scanner.consume(TerminalFrame.bytes) == .exhausted)
    }

    @Test("corpo curto demais não casa")
    func aBodyThatIsTooShortDoesNotMatch() {
        var scanner = SetupTokenScanner()

        #expect(scanner.consume("sk-ant-oat01-" + String(repeating: "a", count: 19) + " fim") == .pending)
    }

    @Test("o corpo mais curto aceitável casa, e é o menor que casa")
    func theShortestAcceptableBodyMatches() {
        var scanner = SetupTokenScanner()
        let shortest = "sk-ant-oat01-" + String(repeating: "a", count: SetupTokenScanner.minimumBodyLength)

        #expect(scanner.consume(shortest + " fim") == .found(shortest))
    }

    @Test("a credencial de outro produto, com outro prefixo, não casa")
    func anotherProductsPrefixDoesNotMatch() {
        var scanner = SetupTokenScanner()
        let consoleKey = "sk-ant-api03-" + String(repeating: "aB9_-=", count: 16)

        #expect(scanner.consume(consoleKey + "\r\n") == .pending)
    }

    @Test("o casamento é maximal: o corpo vai até o último byte do alfabeto esperado")
    func theMatchIsMaximal() {
        var scanner = SetupTokenScanner()
        let long = "sk-ant-oat01-" + String(repeating: "aB9_-=", count: 16) + "ZZZZ"

        #expect(scanner.consume(long + "\r\n") == .found(long))
    }

    @Test("o casamento para no comprimento máximo do token, mesmo com o alfabeto continuando")
    func theMatchStopsAtTheMaximumTokenLength() {
        var scanner = SetupTokenScanner()
        let overlong = "sk-ant-oat01-" + String(repeating: "a", count: SetupTokenScanner.maxTokenLength)

        #expect(scanner.consume(overlong) == .found(String(overlong.prefix(SetupTokenScanner.maxTokenLength))))
    }

    @Test("a janela retém apenas a cauda que ainda pode formar um token, e zera o restante")
    func theWindowKeepsOnlyTheTailAndZeroesTheRest() {
        var scanner = SetupTokenScanner()

        #expect(scanner.consume([UInt8](repeating: 0x78, count: 4_096)) == .pending)
        #expect(scanner.retainedLength == SetupTokenScanner.maxTokenLength - 1)
        #expect(scanner.retainedBytes[scanner.retainedLength...].allSatisfy { $0 == 0 })
    }

    @Test("limpar a janela zera a memória dela, não apenas o comprimento")
    func wipingTheWindowZeroesItsMemory() {
        var scanner = SetupTokenScanner()

        _ = scanner.consume(TerminalFrame.redrawn.replacingOccurrences(of: TerminalFrame.token, with: "x"))
        #expect(scanner.retainedBytes.contains { $0 != 0 })

        scanner.wipe()

        #expect(scanner.retainedLength == 0)
        #expect(scanner.retainedBytes.allSatisfy { $0 == 0 })
    }

    @Test("o token casado não permanece na janela depois de extraído")
    func theMatchedTokenDoesNotStayInTheWindow() {
        var scanner = SetupTokenScanner()

        #expect(scanner.consume(TerminalFrame.bytes) == .found(TerminalFrame.token))
        #expect(scanner.retainedBytes.allSatisfy { $0 == 0 })
    }

    @Test("o varredor devolve texto, e quem julga a forma da credencial continua sendo o portador")
    func theScannerYieldsTextAndTheCredentialTypeRemainsTheJudge() {
        var scanner = SetupTokenScanner()

        guard case .found(let candidate) = scanner.consume(TerminalFrame.bytes) else {
            Issue.record("o fluxo fabricado não casou")
            return
        }

        #expect(SubscriptionToken(pasted: candidate) != nil)
        #expect(candidate.hasPrefix(SetupTokenScanner.expectedPrefix))
    }
}
