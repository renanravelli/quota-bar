public protocol QuotaSnapshotStoring: Sendable {
    func persist(_ snapshot: QuotaSnapshot) async
    func restore() async -> QuotaSnapshot?
}
