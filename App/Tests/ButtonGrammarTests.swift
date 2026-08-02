import Foundation
import QuotaBarCore
import Testing

@testable import QuotaBar

private enum SymbolAvailability {
    static let minimumMacOS = "14.0"

    private static let requiredMacOSBySymbol: [String: String] = {
        let path = "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist"
        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let database = plist as? [String: Any],
              let trains = database["symbols"] as? [String: Any],
              let releases = database["year_to_release"] as? [String: Any]
        else { return [:] }

        return trains.reduce(into: [:]) { required, entry in
            guard let release = releases["\(entry.value)"] as? [String: Any],
                  let macOS = release["macOS"]
            else { return }

            required[entry.key] = "\(macOS)"
        }
    }()

    static func macOSRequired(by symbol: String) -> String? {
        requiredMacOSBySymbol[symbol]
    }

    static func exceeds(_ version: String, _ other: String) -> Bool {
        let left = version.split(separator: ".").map { Int($0) ?? 0 }
        let right = other.split(separator: ".").map { Int($0) ?? 0 }

        for position in 0..<max(left.count, right.count) {
            let first = position < left.count ? left[position] : 0
            let second = position < right.count ? right[position] : 0
            if first != second { return first > second }
        }
        return false
    }
}

private enum AppLayout {
    static let root = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static var viewSources: [URL] {
        let directory = root.appending(path: "App").appending(path: "Sources").appending(path: "Views")
        let contents = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        return (contents?.compactMap { $0 as? URL } ?? []).filter { $0.pathExtension == "swift" }
    }

    static func text(of source: URL) throws -> String {
        try String(contentsOf: source, encoding: .utf8)
    }

    static func buttonsBuiltOutsideTheGrammar(in text: String) -> Int {
        var found = 0
        var searchStart = text.startIndex

        while let range = text.range(of: "Button(", range: searchStart..<text.endIndex) {
            let precededByIdentifier: Bool
            if range.lowerBound > text.startIndex {
                let previous = text[text.index(before: range.lowerBound)]
                precededByIdentifier = previous.isLetter || previous.isNumber || previous == "_"
            } else {
                precededByIdentifier = false
            }

            if !precededByIdentifier { found += 1 }
            searchStart = range.upperBound
        }

        return found
    }

    static func actionsDrawn(in text: String) -> Set<String> {
        var drawn: Set<String> = []
        var searchStart = text.startIndex

        while let range = text.range(of: "ActionButton(action: .", range: searchStart..<text.endIndex) {
            let rest = text[range.upperBound...]
            let name = rest.prefix { $0.isLetter || $0.isNumber }
            if !name.isEmpty { drawn.insert(String(name)) }
            searchStart = range.upperBound
        }

        return drawn
    }
}

@Suite("Gramática de botões")
struct ButtonGrammarTests {
    private static let formsDeclaredBySpec: [ButtonAction: ButtonForm] = [
        .quit: .pictogramOnly,
        .openUsageScreen: .pictogramOnly,
        .returnToPreviousSurface: .pictogramOnly,
        .copyCommand: .pictogramOnly,
        .configureCredential: .pictogramWithText,
        .startAssistedSetup: .pictogramWithText,
        .submitAuthorizationCode: .pictogramWithText,
        .saveCredential: .pictogramWithText,
        .replaceCredential: .pictogramWithText,
        .removeCredential: .pictogramWithText,
        .cancelConduction: .pictogramWithText
    ]

    private static let symbolsDeclaredBySpec: [ButtonAction: String] = [
        .quit: "power",
        .openUsageScreen: "chart.xyaxis.line",
        .returnToPreviousSurface: "chevron.backward",
        .copyCommand: "doc.on.doc",
        .configureCredential: "key",
        .startAssistedSetup: "wand.and.stars",
        .submitAuthorizationCode: "arrow.right.circle",
        .saveCredential: "checkmark.shield",
        .replaceCredential: "arrow.triangle.2.circlepath",
        .removeCredential: "trash",
        .cancelConduction: "xmark.circle"
    ]

    static let titlesInTheProduct: [ButtonAction: String] = [
        .quit: PanelText.quit,
        .configureCredential: PanelText.configureCredential,
        .copyCommand: CredentialSetupText.copyCommand,
        .startAssistedSetup: CredentialSetupText.assist,
        .submitAuthorizationCode: CredentialSetupText.send,
        .saveCredential: CredentialSetupText.save,
        .replaceCredential: CredentialSetupText.replace,
        .removeCredential: CredentialSetupText.remove,
        .cancelConduction: CredentialSetupText.cancel
    ]

    @Test("a forma de cada ação sai das três condições, e é a que a tabela aprovada declara")
    func eachActionCarriesTheFormItsConditionsProduce() {
        for action in ButtonAction.allCases {
            let expected = Self.formsDeclaredBySpec[action]
            #expect(expected != nil, "ação sem forma declarada na tabela: \(action)")
            #expect(action.form == expected, "\(action) desenhada fora da forma que a tabela declara")
            #expect(action.form == action.conditions.requiredForm)
        }
    }

    @Test("cada ação desenha o pictograma que a tabela aprovada fixa")
    func eachActionDrawsTheSymbolTheTableFixes() {
        for action in ButtonAction.allCases {
            #expect(action.symbolName == Self.symbolsDeclaredBySpec[action], "\(action) trocou de desenho")
        }
    }

    @Test("as três condições valendo juntas são o que dispensa o texto ao lado do pictograma")
    func allThreeConditionsTogetherDropTheText() {
        let conditions = ActionConditions(
            hasEstablishedConvention: true,
            destroysNothing: true,
            mistakeUndoneInOneGesture: true
        )

        #expect(conditions.requiredForm == .pictogramOnly)
    }

    @Test("falhar em uma única condição já obriga o texto ao lado do pictograma")
    func failingASingleConditionForcesTheText() {
        let withoutConvention = ActionConditions(
            hasEstablishedConvention: false,
            destroysNothing: true,
            mistakeUndoneInOneGesture: true
        )
        let thatDestroys = ActionConditions(
            hasEstablishedConvention: true,
            destroysNothing: false,
            mistakeUndoneInOneGesture: true
        )
        let hardToUndo = ActionConditions(
            hasEstablishedConvention: true,
            destroysNothing: true,
            mistakeUndoneInOneGesture: false
        )

        #expect(withoutConvention.requiredForm == .pictogramWithText)
        #expect(thatDestroys.requiredForm == .pictogramWithText)
        #expect(hardToUndo.requiredForm == .pictogramWithText)
    }

    @Test("as ações que gravam, substituem, removem ou cancelam nunca aparecem sem texto")
    func credentialAndCancellationActionsNeverDropTheText() {
        let mustCarryText: [ButtonAction] = [
            .saveCredential, .replaceCredential, .removeCredential, .cancelConduction, .configureCredential
        ]

        for action in mustCarryText {
            #expect(action.form == .pictogramWithText, "\(action) apareceu sem texto ao lado")
        }
    }

    @Test("nenhum pictograma de ação exige sistema mais novo que o alvo mínimo")
    func noActionSymbolRequiresANewerSystemThanTheMinimumTarget() throws {
        for action in ButtonAction.allCases {
            let required = try #require(
                SymbolAvailability.macOSRequired(by: action.symbolName),
                "a base do sistema não conhece '\(action.symbolName)'"
            )

            #expect(
                !SymbolAvailability.exceeds(required, SymbolAvailability.minimumMacOS),
                "\(action.symbolName) exige macOS \(required), acima do alvo mínimo"
            )
        }
    }

    @Test("sem o pictograma o botão continua nomeado, e o nome é o texto da ação")
    func withoutThePictogramTheButtonKeepsItsName() {
        for action in ButtonAction.allCases {
            let title = Self.titlesInTheProduct[action] ?? "Ação prevista"
            let rendering = action.rendering(titled: title, symbolIsRenderable: false)

            #expect(rendering == .textOnly(title: title), "\(action) perdeu o nome sem o pictograma")
            #expect(!rendering.name.isEmpty)
        }
    }

    @Test("com o pictograma disponível a forma desenhada é a que a regra determina")
    func withThePictogramAvailableTheDrawnFormFollowsTheRule() {
        for action in ButtonAction.allCases {
            let title = Self.titlesInTheProduct[action] ?? "Ação prevista"
            let rendering = action.rendering(titled: title, symbolIsRenderable: true)

            switch action.form {
            case .pictogramOnly:
                #expect(rendering == .pictogram(symbol: action.symbolName, name: title))
            case .pictogramWithText:
                #expect(rendering == .pictogramWithText(symbol: action.symbolName, title: title))
            }
            #expect(rendering.name == title)
        }
    }

    @Test("o pictograma se distingue da superfície em que é desenhado")
    func thePictogramStandsOutFromItsSurface() {
        for role in [PictogramRole.ordinary, .emphasis, .destructive] {
            for surface in [Palette.surface, Palette.background] {
                #expect(
                    Contrast.ratio(role.color, surface) >= 3,
                    "\(role.color.hexString) sobre \(surface.hexString) não alcança 3:1"
                )
            }
        }
    }

    @Test("a ação destrutiva também alcança o contraste exigido do texto que a acompanha")
    func theDestructiveActionAlsoMeetsTheTextContrast() {
        #expect(Contrast.ratio(PictogramRole.destructive.color, Palette.surface) >= Contrast.minimumRatio)
    }

    @Test("o rótulo de encerrar diz que encerra o QuotaBar")
    func theQuitLabelSaysItQuitsQuotaBar() {
        #expect(PanelText.quit.contains("QuotaBar"))
    }

    @Test("nenhum rótulo de botão nomeia o desenho em vez da ação")
    func noButtonLabelNamesTheDrawing() {
        for (action, title) in Self.titlesInTheProduct {
            let drawingWords = action.symbolName
                .split(separator: ".")
                .map(String.init)
                .filter { $0.count >= 4 }

            for word in drawingWords {
                #expect(
                    !title.lowercased().contains(word.lowercased()),
                    "o rótulo de \(action) nomeia o desenho: '\(title)'"
                )
            }
        }
    }
}

@Suite("Inventário de botões do aplicativo")
struct AppButtonInventoryTests {
    @Test("todo botão desenhado nas telas passa pela tabela de ações")
    func everyButtonDrawnGoesThroughTheTable() throws {
        let sources = AppLayout.viewSources
        #expect(!sources.isEmpty, "nenhuma tela encontrada para inventariar")

        for source in sources where source.lastPathComponent != "ActionButton.swift" {
            let raw = AppLayout.buttonsBuiltOutsideTheGrammar(in: try AppLayout.text(of: source))

            #expect(raw == 0, "\(source.lastPathComponent) constrói \(raw) botão(ões) fora da tabela")
        }
    }

    @Test("toda ação cuja superfície já existe está desenhada em alguma tela")
    func everyBuiltSurfaceActionIsDrawnSomewhere() throws {
        var drawn: Set<String> = []
        for source in AppLayout.viewSources {
            drawn.formUnion(AppLayout.actionsDrawn(in: try AppLayout.text(of: source)))
        }

        for action in ButtonAction.allCases where action.surface == .built {
            #expect(drawn.contains("\(action)"), "a ação \(action) não está desenhada em tela nenhuma")
        }
    }

    @Test("ação de superfície ainda não construída não aparece desenhada")
    func actionsOfUnbuiltSurfacesAreNotDrawnYet() throws {
        var drawn: Set<String> = []
        for source in AppLayout.viewSources {
            drawn.formUnion(AppLayout.actionsDrawn(in: try AppLayout.text(of: source)))
        }

        for action in ButtonAction.allCases where action.surface == .planned {
            #expect(!drawn.contains("\(action)"), "a ação \(action) foi desenhada antes de a superfície existir")
        }
    }

    @Test("o nome do botão vai ao mesmo tempo para o leitor de tela e para a dica do ponteiro")
    func theButtonNameReachesBothTheScreenReaderAndThePointerHint() throws {
        let source = try #require(AppLayout.viewSources.first { $0.lastPathComponent == "ActionButton.swift" })
        let text = try AppLayout.text(of: source)

        #expect(text.contains(".accessibilityLabel(Text(title))"))
        #expect(text.contains(".help(title)"))
    }
}
