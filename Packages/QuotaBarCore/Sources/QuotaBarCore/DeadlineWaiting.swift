import Foundation

public protocol DeadlineWaiting: Sendable {
    func wait(until deadline: Date) async
}

public struct SystemDeadlineWaiter: DeadlineWaiting {
    private let time: any DateProviding

    public init(time: any DateProviding = SystemDate()) {
        self.time = time
    }

    public func wait(until deadline: Date) async {
        let seconds = deadline.timeIntervalSince(time.now)
        guard seconds > 0 else { return }
        try? await Task.sleep(for: .seconds(seconds))
    }
}
