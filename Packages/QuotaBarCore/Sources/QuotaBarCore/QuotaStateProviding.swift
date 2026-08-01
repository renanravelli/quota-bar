public protocol QuotaStateProviding: Sendable {
    var states: AsyncStream<QuotaState> { get }
    func refreshNow() async
    func setViewerObserving(_ observing: Bool) async
}
