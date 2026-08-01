import Foundation
import QuotaBarCore

public actor FileQuotaSampleLog: QuotaSampleLogging {
    public static let applicationSupport = FileQuotaSampleLog(fileURL: applicationSupportFileURL)

    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func append(_ sample: QuotaSample) async {
        var series = restored()
        guard series.append(sample) else { return }

        persist(QuotaSampleRetention.retained(series.samples))
    }

    public func load(since: Date) async -> QuotaSampleSeries {
        let series = restored()

        return QuotaSampleSeries(
            series.samples.filter { $0.readAt >= since },
            restoration: series.restoration
        )
    }

    private func restored() -> QuotaSampleSeries {
        guard let data = try? Data(contentsOf: fileURL) else { return QuotaSampleSeries() }

        guard let stored = try? JSONDecoder().decode(StoredSampleLog.self, from: data),
              stored.version == StoredSampleLog.currentVersion
        else { return QuotaSampleSeries(restoration: .restartedAfterUnreadableLog) }

        let samples = stored.samples.compactMap(\.sample)
        guard samples.count == stored.samples.count else {
            return QuotaSampleSeries(restoration: .restartedAfterUnreadableLog)
        }

        return QuotaSampleSeries(samples)
    }

    private func persist(_ samples: [QuotaSample]) {
        let stored = StoredSampleLog(version: StoredSampleLog.currentVersion, samples: samples.map(StoredSample.init))
        guard let data = try? JSONEncoder().encode(stored) else { return }

        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }

    private static var applicationSupportFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(filePath: NSHomeDirectory()).appending(path: "Library/Application Support")

        return base
            .appending(path: "QuotaBar", directoryHint: .isDirectory)
            .appending(path: "quota-series.json", directoryHint: .notDirectory)
    }
}

private struct StoredSampleLog: Codable {
    static let currentVersion = 1

    let version: Int
    let samples: [StoredSample]
}

private struct StoredSample: Codable {
    let readAt: Date
    let readSequence: UInt64
    let fiveHourBasisPoints: Int?
    let sevenDayBasisPoints: Int?
    let fiveHourResetsAt: Date?
    let sevenDayResetsAt: Date?
    let source: String

    init(_ sample: QuotaSample) {
        readAt = sample.readAt
        readSequence = sample.readSequence
        fiveHourBasisPoints = sample.fiveHour?.basisPoints
        sevenDayBasisPoints = sample.sevenDay?.basisPoints
        fiveHourResetsAt = sample.fiveHourResetsAt
        sevenDayResetsAt = sample.sevenDayResetsAt
        source = SampleSourceVocabulary.text(of: sample.source)
    }

    var sample: QuotaSample? {
        guard let restoredSource = SampleSourceVocabulary.source(from: source),
              isRepresentableUtilization(fiveHourBasisPoints),
              isRepresentableUtilization(sevenDayBasisPoints)
        else { return nil }

        return QuotaSample(
            readAt: readAt,
            readSequence: readSequence,
            fiveHour: fiveHourBasisPoints.flatMap(Utilization.init(basisPoints:)),
            sevenDay: sevenDayBasisPoints.flatMap(Utilization.init(basisPoints:)),
            fiveHourResetsAt: fiveHourResetsAt,
            sevenDayResetsAt: sevenDayResetsAt,
            source: restoredSource
        )
    }

    private func isRepresentableUtilization(_ basisPoints: Int?) -> Bool {
        guard let basisPoints else { return true }
        return Utilization(basisPoints: basisPoints) != nil
    }
}

private enum SampleSourceVocabulary {
    static func text(of source: QuotaSource) -> String {
        switch source {
        case .primaryProbe: "primary_probe"
        case .contingencyStatusLine: "contingency_status_line"
        }
    }

    static func source(from text: String) -> QuotaSource? {
        switch text {
        case "primary_probe": .primaryProbe
        case "contingency_status_line": .contingencyStatusLine
        default: nil
        }
    }
}
