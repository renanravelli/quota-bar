import Foundation
import QuotaBarCore

public protocol QuotaSampleLogging: Sendable {
    func append(_ sample: QuotaSample) async
    func load(since: Date) async -> QuotaSampleSeries
}
