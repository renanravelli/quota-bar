import AppKit
import Foundation
import Observation
import QuotaBarCore

@MainActor
@Observable
final class AccessibilityPreferences {
    private(set) var reduceMotion: ReduceMotionPreference
    private(set) var reduceTransparency: Bool

    @ObservationIgnored private let read: @Sendable () -> (ReduceMotionPreference, Bool)
    @ObservationIgnored private let center: NotificationCenter
    @ObservationIgnored nonisolated(unsafe) private var observer: NSObjectProtocol?

    init(
        read: @escaping @Sendable () -> (ReduceMotionPreference, Bool) = AccessibilityPreferences.systemRead,
        center: NotificationCenter = NSWorkspace.shared.notificationCenter,
        notificationName: Notification.Name = NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
    ) {
        self.read = read
        self.center = center

        let current = read()
        reduceMotion = current.0
        reduceTransparency = current.1

        observer = center.addObserver(forName: notificationName, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    deinit {
        if let observer {
            center.removeObserver(observer)
        }
    }

    func refresh() {
        let current = read()
        if current.0 != reduceMotion {
            reduceMotion = current.0
        }
        if current.1 != reduceTransparency {
            reduceTransparency = current.1
        }
    }

    nonisolated static func systemRead() -> (ReduceMotionPreference, Bool) {
        (SystemAccessibility.reduceMotion(), SystemAccessibility.reduceTransparency())
    }
}
