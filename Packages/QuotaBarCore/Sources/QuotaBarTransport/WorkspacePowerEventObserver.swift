import AppKit
import Foundation
import QuotaBarCore

public struct WorkspacePowerEventObserver: SystemPowerEventObserving {
    private static let announcements: [Notification.Name: SystemPowerEvent] = [
        NSWorkspace.willSleepNotification: .willSleep,
        NSWorkspace.didWakeNotification: .didWake
    ]

    let center: NotificationCenter

    public init(center: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.center = center
    }

    public var powerEvents: AsyncStream<SystemPowerEvent> {
        let workspace = UncheckedSendable(center)
        return AsyncStream { continuation in
            let registrations = Self.announcements.map { name, event in
                UncheckedSendable(
                    workspace.value.addObserver(forName: name, object: nil, queue: nil) { _ in
                        continuation.yield(event)
                    }
                )
            }

            continuation.onTermination = { _ in
                registrations.forEach { workspace.value.removeObserver($0.value) }
            }
        }
    }
}
