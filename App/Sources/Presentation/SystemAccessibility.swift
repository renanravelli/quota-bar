import AppKit
import QuotaBarCore

enum SystemAccessibility {
    static func reduceMotion() -> ReduceMotionPreference {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .on : .off
    }

    static func reduceTransparency() -> Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
}
