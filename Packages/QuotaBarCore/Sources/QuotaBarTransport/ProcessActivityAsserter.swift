import Foundation
import QuotaBarCore

public struct ProcessActivityAsserter: SystemActivityAsserting {
    static let options: ProcessInfo.ActivityOptions = .userInitiatedAllowingIdleSystemSleep
    private static let reason = "reading the quota window"

    public init() {}

    public func beginProbeActivity() -> SystemActivityAssertion {
        let token = UncheckedSendable(
            ProcessInfo.processInfo.beginActivity(options: Self.options, reason: Self.reason)
        )
        return SystemActivityAssertion {
            ProcessInfo.processInfo.endActivity(token.value)
        }
    }
}
