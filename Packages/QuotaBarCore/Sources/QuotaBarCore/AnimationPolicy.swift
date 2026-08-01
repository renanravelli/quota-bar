public enum ReduceMotionPreference: Sendable, Hashable {
    case on
    case off
    case undetermined
}

public enum AnimationPolicy {
    public static func shouldAnimate(_ preference: ReduceMotionPreference) -> Bool {
        switch preference {
        case .off: true
        case .on, .undetermined: false
        }
    }
}
