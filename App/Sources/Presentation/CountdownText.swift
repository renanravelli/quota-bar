import QuotaBarCore

enum CountdownText {
    static func text(remaining: Duration, format: CountdownFormat) -> String {
        let total = max(0, remaining.components.seconds)

        switch format {
        case .withSeconds:
            return String(format: "%d:%02d", total / 60, total % 60)
        case .minutesOnly:
            let hours = total / 3600
            if hours >= 24 {
                return "\(hours / 24)d \(hours % 24)h"
            }
            return "\(hours)h \((total % 3600) / 60)min"
        }
    }
}
