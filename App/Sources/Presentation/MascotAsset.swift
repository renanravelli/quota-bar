import AppKit
import QuotaBarCore

enum MascotAsset {
    static func imageName(for expression: MascotExpression) -> String {
        switch expression {
        case .normal: "MascotNormal"
        case .attention: "MascotAttention"
        case .critical: "MascotCritical"
        case .exhausted: "MascotExhausted"
        case .noValue: "MascotNoValue"
        }
    }

    static func image(for expression: MascotExpression, in bundle: Bundle = .main) -> NSImage? {
        bundle.image(forResource: imageName(for: expression))
    }
}
