public struct ScannedRow: Sendable, Hashable {
    public let key: UsageKey?
    public let offset: Int64
    public let length: Int64

    public init(key: UsageKey?, offset: Int64, length: Int64) {
        self.key = key
        self.offset = offset
        self.length = length
    }

    public var endOffset: Int64 { offset + length }
}

public struct ResumePoint: Sendable, Hashable {
    public let offset: Int64
    public let tailKey: UsageKey?

    public init(offset: Int64, tailKey: UsageKey?) {
        self.offset = offset
        self.tailKey = tailKey
    }
}

public enum ResumePolicy {
    public static func resumePoint(afterFolding rows: [ScannedRow]) -> ResumePoint {
        let consumed = rows.last?.endOffset ?? 0

        guard let tailIndex = rows.lastIndex(where: { $0.key != nil }),
              let tailKey = rows[tailIndex].key
        else { return ResumePoint(offset: consumed, tailKey: nil) }

        var groupStart = tailIndex
        var cursor = tailIndex - 1
        while cursor >= 0 {
            if let key = rows[cursor].key {
                guard key == tailKey else { break }
                groupStart = cursor
            }
            cursor -= 1
        }

        return ResumePoint(offset: rows[groupStart].offset, tailKey: tailKey)
    }
}
