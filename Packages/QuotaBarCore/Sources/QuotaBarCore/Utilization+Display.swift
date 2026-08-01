extension Utilization {
    private static let highestDisplayablePercent = 100

    public var displayablePercent: Int {
        min(truncatedPercent, Self.highestDisplayablePercent)
    }
}
