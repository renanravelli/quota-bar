public enum CadenceFillPolicy {
    public static let stepsPerCadence = 120
    public static let fastest: Duration = .seconds(1)
    public static let slowest: Duration = .seconds(5)

    public static func refreshInterval(for interval: Duration) -> Duration {
        min(max(interval / stepsPerCadence, fastest), slowest)
    }
}
