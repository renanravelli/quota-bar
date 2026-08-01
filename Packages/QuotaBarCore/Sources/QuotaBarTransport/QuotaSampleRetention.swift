import Foundation
import QuotaBarCore

public enum QuotaSampleRetention {
    public static let horizon: Duration = .seconds(14 * 24 * 3_600)

    public static func retained(_ samples: [QuotaSample]) -> [QuotaSample] {
        guard let newest = samples.map(\.readAt).max() else { return samples }

        let oldestKept = newest.addingTimeInterval(-Double(horizon.components.seconds))
        return samples.filter { $0.readAt >= oldestKept }
    }
}
