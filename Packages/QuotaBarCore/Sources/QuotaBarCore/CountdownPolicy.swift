public enum CountdownFormat: Sendable, Hashable {
    case withSeconds
    case minutesOnly
}

public enum CountdownPolicy {
    public static let secondsThreshold: Duration = .seconds(3600)

    public static func format(remaining: Duration) -> CountdownFormat {
        remaining < secondsThreshold ? .withSeconds : .minutesOnly
    }

    public static func refreshInterval(for format: CountdownFormat) -> Duration {
        switch format {
        case .withSeconds: .seconds(1)
        case .minutesOnly: .seconds(60)
        }
    }
}
