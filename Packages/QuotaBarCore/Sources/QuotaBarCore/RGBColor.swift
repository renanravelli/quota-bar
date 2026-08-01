import Foundation

public struct RGBColor: Sendable, Hashable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = Self.clamped(red)
        self.green = Self.clamped(green)
        self.blue = Self.clamped(blue)
    }

    public init?(hex: String) {
        var digits = hex
        if digits.hasPrefix("#") { digits.removeFirst() }

        guard digits.count == 6, let packed = UInt32(digits, radix: 16) else { return nil }

        self.init(
            red: Double((packed >> 16) & 0xFF) / 255,
            green: Double((packed >> 8) & 0xFF) / 255,
            blue: Double(packed & 0xFF) / 255
        )
    }

    public var hexString: String {
        String(format: "#%02X%02X%02X", channel(red), channel(green), channel(blue))
    }

    private func channel(_ value: Double) -> Int {
        Int((value * 255).rounded())
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

public enum Palette {
    public static let background = RGBColor(hex: "#0F0F12")!
    public static let surface = RGBColor(hex: "#1A1A20")!
    public static let surfaceSecondary = RGBColor(hex: "#24242C")!
    public static let track = RGBColor(hex: "#26262E")!
    public static let grid = RGBColor(hex: "#232329")!
    public static let border = RGBColor(hex: "#30303A")!
    public static let text = RGBColor(hex: "#F2F0EC")!
    public static let textMuted = RGBColor(hex: "#8C8C98")!
    public static let structuralWeak = RGBColor(hex: "#5C5C68")!
    public static let accent = RGBColor(hex: "#D97757")!
    public static let ok = RGBColor(hex: "#4ADE80")!
    public static let warning = RGBColor(hex: "#FBBF24")!
    public static let bad = RGBColor(hex: "#F87171")!

    public static let textColors: [RGBColor] = [text, textMuted]
    public static let surfaces: [RGBColor] = [background, surface, surfaceSecondary, track]
    public static let forbiddenAsTextColor: [RGBColor] = [structuralWeak, track]
}

public enum Contrast {
    public static let minimumRatio = 4.5

    public static func relativeLuminance(_ color: RGBColor) -> Double {
        0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    public static func ratio(_ a: RGBColor, _ b: RGBColor) -> Double {
        let first = relativeLuminance(a)
        let second = relativeLuminance(b)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private static func linear(_ channel: Double) -> Double {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
}
