public enum BackoffPolicy {
    public static let ceiling: Duration = .seconds(1800)

    public static func widened(from current: Duration, retryAfter: Duration?, jitter: Double) -> Duration {
        if let retryAfter {
            return max(retryAfter, Cadence.floor)
        }
        let jittered = current * (1 + min(max(jitter, 0), 1))
        return min(max(jittered, Cadence.floor), ceiling)
    }
}
