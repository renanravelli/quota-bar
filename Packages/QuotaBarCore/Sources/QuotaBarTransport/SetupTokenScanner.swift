import Darwin

private enum ControlByte {
    static let escape: UInt8 = 0x1B
    static let bell: UInt8 = 0x07
    static let controlSequenceIntroducer: UInt8 = 0x5B
    static let stringIntroducers: Set<UInt8> = [0x50, 0x5D, 0x58, 0x5E, 0x5F]
    static let characterSetIntroducers: Set<UInt8> = [0x23, 0x25, 0x28, 0x29, 0x2A, 0x2B]
    static let sequenceTerminators: ClosedRange<UInt8> = 0x40...0x7E
}

private struct EscapeFilter {
    private enum State {
        case text
        case introduction
        case controlSequence
        case string
        case stringTermination
        case characterSet
    }

    private var state = State.text

    mutating func admits(_ byte: UInt8) -> Bool {
        switch state {
        case .text:
            guard byte == ControlByte.escape else { return true }
            state = .introduction
        case .introduction:
            state = Self.state(introducedBy: byte)
        case .controlSequence:
            if ControlByte.sequenceTerminators.contains(byte) { state = .text }
        case .string:
            if byte == ControlByte.bell { state = .text }
            if byte == ControlByte.escape { state = .stringTermination }
        case .stringTermination, .characterSet:
            state = .text
        }

        return false
    }

    mutating func reset() {
        state = .text
    }

    private static func state(introducedBy byte: UInt8) -> State {
        if byte == ControlByte.controlSequenceIntroducer { return .controlSequence }
        if ControlByte.stringIntroducers.contains(byte) { return .string }
        if ControlByte.characterSetIntroducers.contains(byte) { return .characterSet }
        return .text
    }
}

private struct ScanWindow {
    private(set) var bytes: [UInt8]
    private(set) var length = 0

    init(capacity: Int) {
        bytes = [UInt8](repeating: 0, count: capacity)
    }

    mutating func append(_ byte: UInt8) {
        bytes[length] = byte
        length += 1
    }

    mutating func retainTail(_ tailLength: Int) {
        guard length > tailLength else { return }

        let dropped = length - tailLength
        bytes.withUnsafeMutableBytes { region in
            guard let base = region.baseAddress else { return }
            memmove(base, base + dropped, tailLength)
            SecretBuffer.zero(
                UnsafeMutableRawBufferPointer(start: base + tailLength, count: region.count - tailLength)
            )
        }
        length = tailLength
    }

    mutating func wipe() {
        SecretBuffer.zero(&bytes)
        length = 0
    }
}

public struct SetupTokenScanner: Sendable {
    public enum Outcome: Sendable, Hashable {
        case pending
        case found(String)
        case exhausted
    }

    public static let expectedPrefix = "sk-ant-oat01-"
    public static let maxTokenLength = 512
    public static let minimumBodyLength = 20
    public static let scanLimit = 1 << 20

    private static let prefix = Array(expectedPrefix.utf8)
    private static let retainedTailLength = maxTokenLength - 1
    private static let passLength = 1 << 16

    private var window = ScanWindow(capacity: retainedTailLength + passLength)
    private var escapes = EscapeFilter()
    private var consumedBytes = 0
    private var settled: Outcome?

    public init() {}

    var retainedBytes: [UInt8] { window.bytes }

    var retainedLength: Int { window.length }

    public mutating func consume(_ chunk: UnsafeRawBufferPointer) -> Outcome {
        if let settled { return settled }

        consumedBytes += chunk.count

        var offset = 0
        while offset < chunk.count {
            let end = min(offset + Self.passLength, chunk.count)
            for byte in chunk[offset..<end] where escapes.admits(byte) {
                window.append(byte)
            }
            offset = end

            if let token = matchedToken() {
                window.wipe()
                settled = .found(token)
                return .found(token)
            }
            window.retainTail(Self.retainedTailLength)
        }

        guard consumedBytes >= Self.scanLimit else { return .pending }

        window.wipe()
        settled = .exhausted
        return .exhausted
    }

    public mutating func wipe() {
        window.wipe()
        escapes.reset()
        consumedBytes = 0
        settled = nil
    }

    private func matchedToken() -> String? {
        var start = 0

        while start + Self.prefix.count <= window.length {
            guard startsWithPrefix(at: start) else {
                start += 1
                continue
            }

            var end = start + Self.prefix.count
            while end < window.length, Self.isBodyByte(window.bytes[end]), end - start < Self.maxTokenLength {
                end += 1
            }

            let isComplete = end < window.length || end - start == Self.maxTokenLength
            guard isComplete else { return nil }

            if end - start - Self.prefix.count >= Self.minimumBodyLength {
                return String(decoding: window.bytes[start..<end], as: UTF8.self)
            }
            start += 1
        }

        return nil
    }

    private func startsWithPrefix(at start: Int) -> Bool {
        for offset in 0..<Self.prefix.count where window.bytes[start + offset] != Self.prefix[offset] {
            return false
        }
        return true
    }

    private static func isBodyByte(_ byte: UInt8) -> Bool {
        switch byte {
        case 0x41...0x5A, 0x61...0x7A, 0x30...0x39: true
        case 0x2D, 0x3D, 0x5F: true
        default: false
        }
    }
}
