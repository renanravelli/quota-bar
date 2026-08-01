import Foundation

public enum AgeDisplay {
    public static func phrase(for age: Duration) -> String {
        let seconds = max(0, age.components.seconds)

        if seconds < minute { return "há menos de um minuto" }
        if seconds < hour { return count(seconds / minute, "minuto", "minutos") }
        return count(seconds / hour, "hora", "horas")
    }

    public static func nextChange(ofReadingAt readAt: Date, now: Date) -> Date? {
        let seconds = StalenessPolicy.age(ofReadingAt: readAt, now: now).components.seconds
        let granularity = seconds < hour ? minute : hour
        let change = readAt.addingTimeInterval(TimeInterval((seconds / granularity + 1) * granularity))

        return change > now ? change : nil
    }

    private static let minute: Int64 = 60
    private static let hour: Int64 = 3_600

    private static func count(_ value: Int64, _ singular: String, _ plural: String) -> String {
        "há \(value) \(value == 1 ? singular : plural)"
    }
}
