import Foundation
import QuotaBarCore
import os

final class InMemorySnapshotStore: QuotaSnapshotStoring, Sendable {
    private let held: OSAllocatedUnfairLock<QuotaSnapshot?>

    init(_ snapshot: QuotaSnapshot? = nil) {
        held = OSAllocatedUnfairLock(initialState: snapshot)
    }

    var current: QuotaSnapshot? {
        held.withLock { $0 }
    }

    func persist(_ snapshot: QuotaSnapshot) async {
        held.withLock { $0 = snapshot }
    }

    func restore() async -> QuotaSnapshot? {
        held.withLock { $0 }
    }
}
