import AppKit
import Testing

@Suite("Desenho do item na barra de menus")
struct MenuBarItemDrawingTests {
    private static let pollInterval = Duration.milliseconds(100)
    private static let polls = 120

    @Test("o texto do indicador chega desenhado no item da barra, e não só o símbolo")
    @MainActor
    func theIndicatorTextReachesTheBarItemAndNotOnlyTheSymbol() async throws {
        let drawn = try #require(
            await Self.titleDrawnOnTheBarItem(),
            "o item da barra ficou sem título enquanto o indicador tinha texto a mostrar"
        )

        #expect(drawn.wholeMatch(of: /(5h|7d) ~?\d{1,3}%/) != nil, "título desenhado: '\(drawn)'")
        #expect(Self.barButton()?.image != nil, "o símbolo deixou de acompanhar o texto")
    }

    @MainActor
    private static func titleDrawnOnTheBarItem() async -> String? {
        for _ in 0..<polls {
            if let title = barButton()?.title, !title.isEmpty { return title }
            try? await Task.sleep(for: pollInterval)
        }
        return nil
    }

    @MainActor
    private static func barButton() -> NSButton? {
        NSApp.windows
            .filter { String(describing: type(of: $0)).contains("StatusBar") }
            .compactMap { $0.contentView.flatMap(button(in:)) }
            .first
    }

    @MainActor
    private static func button(in view: NSView) -> NSButton? {
        if let button = view as? NSButton { return button }
        return view.subviews.lazy.compactMap(button(in:)).first
    }
}
