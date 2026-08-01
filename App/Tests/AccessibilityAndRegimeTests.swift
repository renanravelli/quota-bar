import Foundation
import Testing

@testable import QuotaBar
@testable import QuotaBarCore

private final class PreferenceBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: (ReduceMotionPreference, Bool)

    init(_ value: (ReduceMotionPreference, Bool)) {
        self.value = value
    }

    func read() -> (ReduceMotionPreference, Bool) {
        lock.withLock { value }
    }

    func set(_ newValue: (ReduceMotionPreference, Bool)) {
        lock.withLock { value = newValue }
    }
}

@Suite("Regime do painel")
struct PanelRegimeTests {
    @Test("a animação de entrada cabe no orçamento de 300 ms")
    func entryAnimationFitsTheBudget() {
        #expect(PanelAnimation.entryDuration <= PanelAnimation.visibilityBudget)
        #expect(PanelAnimation.entryDuration == .milliseconds(180))
    }

    @Test("com Reduzir movimento a entrada é instantânea")
    func reduceMotionMakesEntryInstant() {
        #expect(PanelAnimation.entry(shouldAnimate: false) == .zero)
        #expect(PanelAnimation.entry(shouldAnimate: true) == PanelAnimation.entryDuration)
        #expect(PanelAnimation.entry(shouldAnimate: AnimationPolicy.shouldAnimate(.on)) == .zero)
        #expect(PanelAnimation.entry(shouldAnimate: AnimationPolicy.shouldAnimate(.undetermined)) == .zero)
    }

    @Test("as superfícies do painel são opacas e vêm da paleta")
    func panelSurfacesAreOpaqueAndFromThePalette() {
        for surface in PanelSurface.all {
            #expect(Palette.surfaces.contains(surface), "\(surface.hexString) não é superfície da paleta")
        }
        #expect(PanelSurface.background == Palette.background)
    }

    @Test("o contraste mínimo continua satisfeito sobre as superfícies do painel")
    func contrastHoldsOnEveryPanelSurface() {
        for surface in PanelSurface.all {
            for textColor in Palette.textColors {
                #expect(Contrast.ratio(textColor, surface) >= Contrast.minimumRatio)
            }
        }
    }
}

@MainActor
@Suite("Preferências de acessibilidade em tempo de execução")
struct AccessibilityPreferencesTests {
    private static func preferences(
        _ box: PreferenceBox,
        center: NotificationCenter
    ) -> AccessibilityPreferences {
        AccessibilityPreferences(
            read: { box.read() },
            center: center,
            notificationName: .init("TestAccessibilityDisplayOptionsDidChange")
        )
    }

    @Test("a preferência inicial é lida na construção")
    func initialPreferencesAreRead() {
        let box = PreferenceBox((.on, true))
        let preferences = Self.preferences(box, center: NotificationCenter())

        #expect(preferences.reduceMotion == .on)
        #expect(preferences.reduceTransparency)
    }

    @Test("a mudança de Reduzir movimento chega sem reiniciar o aplicativo")
    func reduceMotionChangeArrivesAtRuntime() async {
        let box = PreferenceBox((.off, false))
        let center = NotificationCenter()
        let preferences = Self.preferences(box, center: center)
        #expect(preferences.reduceMotion == .off)

        box.set((.on, false))
        center.post(name: .init("TestAccessibilityDisplayOptionsDidChange"), object: nil)
        await Task.yield()

        #expect(preferences.reduceMotion == .on)
    }

    @Test("a mudança de Reduzir transparência chega sem reabrir o painel")
    func reduceTransparencyChangeArrivesAtRuntime() async {
        let box = PreferenceBox((.off, false))
        let center = NotificationCenter()
        let preferences = Self.preferences(box, center: center)
        #expect(!preferences.reduceTransparency)

        box.set((.off, true))
        center.post(name: .init("TestAccessibilityDisplayOptionsDidChange"), object: nil)
        await Task.yield()

        #expect(preferences.reduceTransparency)
    }

    @Test("as duas preferências mudam juntas e nenhuma anula a outra")
    func bothPreferencesChangeTogether() async {
        let box = PreferenceBox((.off, false))
        let center = NotificationCenter()
        let preferences = Self.preferences(box, center: center)

        box.set((.on, true))
        center.post(name: .init("TestAccessibilityDisplayOptionsDidChange"), object: nil)
        await Task.yield()

        #expect(preferences.reduceMotion == .on)
        #expect(preferences.reduceTransparency)
    }

    @Test("a decisão de animar continua vindo da política, não da preferência crua")
    func theDecisionComesFromThePolicy() async {
        let box = PreferenceBox((.undetermined, false))
        let preferences = Self.preferences(box, center: NotificationCenter())

        #expect(preferences.reduceMotion == .undetermined)
        #expect(!AnimationPolicy.shouldAnimate(preferences.reduceMotion))
    }

    @Test("sem mudança de valor, nada é reescrito")
    func nothingIsRewrittenWithoutAChange() async {
        let box = PreferenceBox((.off, false))
        let center = NotificationCenter()
        let preferences = Self.preferences(box, center: center)

        center.post(name: .init("TestAccessibilityDisplayOptionsDidChange"), object: nil)
        await Task.yield()

        #expect(preferences.reduceMotion == .off)
        #expect(!preferences.reduceTransparency)
    }
}
