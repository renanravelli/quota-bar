import QuotaBarCore
import SwiftUI

extension Color {
    init(_ rgb: QuotaBarCore.RGBColor) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }
}

struct BarSymbolView: View {
    let appearance: SymbolAppearance
    let fallbackSystemName: String

    var body: some View {
        symbol
            .modifier(TintModifier(tint: appearance.tint))
    }

    @ViewBuilder
    private var symbol: some View {
        if let custom = BarSymbolAsset.image(for: appearance) {
            Image(nsImage: custom)
        } else {
            Image(systemName: fallbackSystemName)
        }
    }
}

private struct TintModifier: ViewModifier {
    let tint: SymbolTint

    func body(content: Content) -> some View {
        switch tint {
        case .template:
            content
        case let .colored(rgb):
            content.foregroundStyle(Color(rgb))
        }
    }
}
