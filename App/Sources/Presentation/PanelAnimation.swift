import QuotaBarCore

enum PanelAnimation {
    static let visibilityBudget: Duration = .milliseconds(300)
    static let entryDuration: Duration = .milliseconds(180)
    static let regimeSettlesAfter: Duration = .seconds(2)

    static func entry(shouldAnimate: Bool) -> Duration {
        shouldAnimate ? entryDuration : .zero
    }
}

enum PanelSurface {
    static let background = Palette.background
    static let card = Palette.surface
    static let track = Palette.track

    static let all: [QuotaBarCore.RGBColor] = [background, card, track]
}

extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
