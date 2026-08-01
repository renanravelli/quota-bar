import Foundation
import QuotaBarCore

public struct FileQuotaSnapshotStore: QuotaSnapshotStoring {
    public static let applicationSupport = FileQuotaSnapshotStore(fileURL: applicationSupportFileURL)

    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func persist(_ snapshot: QuotaSnapshot) async {
        guard let data = try? JSONEncoder().encode(StoredReading(snapshot)) else { return }

        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }

    public func restore() async -> QuotaSnapshot? {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode(StoredReading.self, from: data)
        else { return nil }

        return stored.snapshot
    }

    private static var applicationSupportFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(filePath: NSHomeDirectory()).appending(path: "Library/Application Support")

        return base
            .appending(path: "QuotaBar", directoryHint: .isDirectory)
            .appending(path: "last-reading.json", directoryHint: .notDirectory)
    }
}

private struct StoredReading: Codable {
    static let currentVersion = 1

    struct Window: Codable {
        let utilizationBasisPoints: Int?
        let resetsAt: Date?
        let status: String?
    }

    let version: Int
    let fiveHour: Window
    let sevenDay: Window
    let overallStatus: String?
    let nextResetAt: Date?
    let bindingWindow: String?
    let fallbackPercentageBasisPoints: Int?
    let overageStatus: String?
    let overageDisabledReason: String?
    let readSequence: UInt64
    let readAt: Date
    let source: String
}

private extension StoredReading {
    init(_ snapshot: QuotaSnapshot) {
        version = Self.currentVersion
        fiveHour = Window(snapshot.fiveHour)
        sevenDay = Window(snapshot.sevenDay)
        overallStatus = snapshot.overallStatus.map(StoredVocabulary.text(ofStatus:))
        nextResetAt = snapshot.nextResetAt
        bindingWindow = snapshot.bindingWindow.map(StoredVocabulary.text(ofBindingWindow:))
        fallbackPercentageBasisPoints = snapshot.fallbackPercentage?.basisPoints
        overageStatus = snapshot.overage.status
        overageDisabledReason = snapshot.overage.disabledReason
        readSequence = snapshot.readSequence
        readAt = snapshot.readAt
        source = StoredVocabulary.text(ofSource: snapshot.source)
    }

    var snapshot: QuotaSnapshot? {
        guard version == Self.currentVersion,
              let restoredSource = StoredVocabulary.source(from: source),
              [
                  fiveHour.utilizationBasisPoints,
                  sevenDay.utilizationBasisPoints,
                  fallbackPercentageBasisPoints
              ].allSatisfy(Self.isRepresentableUtilization)
        else { return nil }

        return QuotaSnapshot(
            fiveHour: fiveHour.reading,
            sevenDay: sevenDay.reading,
            overallStatus: overallStatus.map(StoredVocabulary.status(from:)),
            nextResetAt: nextResetAt,
            bindingWindow: bindingWindow.map(StoredVocabulary.bindingWindow(from:)),
            fallbackPercentage: fallbackPercentageBasisPoints.flatMap(Utilization.init(basisPoints:)),
            overage: OverageInfo(status: overageStatus, disabledReason: overageDisabledReason),
            readSequence: readSequence,
            readAt: readAt,
            source: restoredSource
        )
    }

    static func isRepresentableUtilization(_ basisPoints: Int?) -> Bool {
        guard let basisPoints else { return true }
        return Utilization(basisPoints: basisPoints) != nil
    }
}

private extension StoredReading.Window {
    init(_ reading: WindowReading) {
        utilizationBasisPoints = reading.utilization?.basisPoints
        resetsAt = reading.resetsAt
        status = reading.status.map(StoredVocabulary.text(ofStatus:))
    }

    var reading: WindowReading {
        WindowReading(
            utilization: utilizationBasisPoints.flatMap(Utilization.init(basisPoints:)),
            resetsAt: resetsAt,
            status: status.map(StoredVocabulary.status(from:))
        )
    }
}

private enum StoredVocabulary {
    static func text(ofStatus status: WindowStatus) -> String {
        switch status {
        case .allowed: "allowed"
        case .allowedWarning: "allowed_warning"
        case .rejected: "rejected"
        case .unknown(let raw): raw
        }
    }

    static func status(from text: String) -> WindowStatus {
        switch text {
        case "allowed": .allowed
        case "allowed_warning": .allowedWarning
        case "rejected": .rejected
        default: .unknown(text)
        }
    }

    static func text(ofBindingWindow window: BindingWindow) -> String {
        switch window {
        case .window(.fiveHour): "five_hour"
        case .window(.sevenDay): "seven_day"
        case .unrecognized(let raw): raw
        }
    }

    static func bindingWindow(from text: String) -> BindingWindow {
        switch text {
        case "five_hour": .window(.fiveHour)
        case "seven_day": .window(.sevenDay)
        default: .unrecognized(text)
        }
    }

    static func text(ofSource source: QuotaSource) -> String {
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
