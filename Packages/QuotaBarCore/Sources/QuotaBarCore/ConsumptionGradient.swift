public enum ConsumptionGradient {
    private static let warningAnchorPercent = 75.0
    private static let highestPercent = 100.0

    public static func color(for utilization: Utilization) -> RGBColor {
        let percent = min(Double(utilization.basisPoints) / 100, highestPercent)

        if percent <= warningAnchorPercent {
            return blend(Palette.ok, Palette.warning, progress: percent / warningAnchorPercent)
        }

        let span = highestPercent - warningAnchorPercent
        return blend(Palette.warning, Palette.bad, progress: (percent - warningAnchorPercent) / span)
    }

    private static func blend(_ start: RGBColor, _ end: RGBColor, progress: Double) -> RGBColor {
        RGBColor(
            red: mix(start.red, end.red, progress),
            green: mix(start.green, end.green, progress),
            blue: mix(start.blue, end.blue, progress)
        )
    }

    private static func mix(_ start: Double, _ end: Double, _ progress: Double) -> Double {
        start * (1 - progress) + end * progress
    }
}
