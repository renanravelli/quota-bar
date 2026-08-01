import Foundation
import QuotaBarCore

enum DecodedLine: Sendable {
    case usable(UsageRecord, producerVersion: String?)
    case unusable(UnusableReason, producerVersion: String?)
    case notUsageBearing
}

enum TranscriptDecoder {
    private static let usageMarker = Data("\"usage\"".utf8)

    private static let fractionalInstant = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let wholeSecondInstant = Date.ISO8601FormatStyle()

    static func decode(line: Data) -> DecodedLine {
        guard line.range(of: usageMarker) != nil else { return .notUsageBearing }

        guard let decoded = try? JSONDecoder().decode(TranscriptLine.self, from: line) else {
            return .unusable(.undecodableLine, producerVersion: nil)
        }

        let version = decoded.version
        guard let usage = decoded.message?.usage else {
            return .unusable(.missingCounters, producerVersion: version)
        }

        let made = UsageRecordFactory.make(
            key: UsageKey(
                messageID: decoded.message?.id,
                requestID: decoded.requestId,
                uuid: decoded.uuid
            ),
            occurredAt: decoded.timestamp.flatMap(instant(from:)),
            model: decoded.message?.model,
            topLevel: raw(usage),
            iterations: (usage.iterations ?? []).map {
                RawIteration(model: $0.model, usage: raw($0))
            }
        )

        return switch made {
        case .success(let record): .usable(record, producerVersion: version)
        case .failure(let reason): .unusable(reason, producerVersion: version)
        }
    }

    static func instant(from text: String) -> Date? {
        (try? fractionalInstant.parse(text)) ?? (try? wholeSecondInstant.parse(text))
    }

    private static func raw(_ usage: TranscriptLine.Message.Usage) -> RawUsage {
        RawUsage(
            input: usage.inputTokens,
            output: usage.outputTokens,
            cacheRead: usage.cacheReadInputTokens,
            cacheCreation: usage.cacheCreationInputTokens
        )
    }

    private static func raw(_ iteration: TranscriptLine.Message.Usage.Iteration) -> RawUsage {
        RawUsage(
            input: iteration.inputTokens,
            output: iteration.outputTokens,
            cacheRead: iteration.cacheReadInputTokens,
            cacheCreation: iteration.cacheCreationInputTokens
        )
    }
}
