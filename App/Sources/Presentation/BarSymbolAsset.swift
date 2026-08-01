import AppKit
import QuotaBarCore

enum BarSymbolAsset {
    static func customName(for appearance: SymbolAppearance) -> String? {
        guard let shape = appearance.shape else { return nil }

        let band = switch shape {
        case .normal: "Normal"
        case .attention: "Attention"
        case .critical: "Critical"
        case .exhausted: "Exhausted"
        }
        let fill = switch appearance.fill {
        case .standard: "Standard"
        case .contingency: "Contingency"
        }

        return "QuotaBarSymbol\(band)\(fill)"
    }

    static func image(for appearance: SymbolAppearance, in bundle: Bundle = .main) -> NSImage? {
        guard let name = customName(for: appearance) else { return nil }
        return bundle.image(forResource: name)
    }
}
