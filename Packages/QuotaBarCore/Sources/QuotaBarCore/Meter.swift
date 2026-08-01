public enum Meter {
    public static let segmentCount = 20

    private static let basisPointsPerSegment = 500

    public static func litSegments(for utilization: Utilization) -> Int {
        let roundedUp = (utilization.basisPoints + basisPointsPerSegment - 1) / basisPointsPerSegment
        return min(roundedUp, segmentCount)
    }
}
