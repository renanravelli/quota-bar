import Foundation
import Observation

@MainActor
@Observable
final class PanelRenderClock {
    @ObservationIgnored private let clock: @Sendable () -> Date

    init(clock: @escaping @Sendable () -> Date = Date.init) {
        self.clock = clock
    }

    var instant: Date {
        access(keyPath: \.instant)
        return clock()
    }

    func mark() {
        withMutation(keyPath: \.instant) {}
    }
}
