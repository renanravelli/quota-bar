import AppKit
import Foundation
import QuotaBarCore
import Testing

@testable import QuotaBarTransport

private func firstEvent(
    of observer: WorkspacePowerEventObserver,
    whilePosting name: Notification.Name,
    on center: NotificationCenter,
    within seconds: Double
) async -> SystemPowerEvent? {
    await withTaskGroup(of: SystemPowerEvent?.self) { group in
        group.addTask {
            var events = observer.powerEvents.makeAsyncIterator()
            return await events.next()
        }
        group.addTask {
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline, !Task.isCancelled {
                center.post(name: name, object: nil)
                try? await Task.sleep(for: .milliseconds(20))
            }
            return nil
        }

        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}

@Suite("Adaptadores de ciclo de vida do sistema", .serialized)
struct SystemLifecycleAdaptersTests {
    @Test("a suspensão e a retomada são ouvidas no centro do NSWorkspace")
    func theObserverListensToTheWorkspaceCenter() {
        let observer = WorkspacePowerEventObserver()

        #expect(observer.center === NSWorkspace.shared.notificationCenter)
        #expect(observer.center !== NotificationCenter.default)
    }

    @Test("a suspensão anunciada pelo centro do NSWorkspace chega")
    func sleepPostedOnTheWorkspaceCenterArrives() async {
        let observer = WorkspacePowerEventObserver()

        let event = await firstEvent(
            of: observer,
            whilePosting: NSWorkspace.willSleepNotification,
            on: NSWorkspace.shared.notificationCenter,
            within: 2
        )

        #expect(event == .willSleep)
    }

    @Test("a retomada anunciada pelo centro do NSWorkspace chega")
    func wakePostedOnTheWorkspaceCenterArrives() async {
        let observer = WorkspacePowerEventObserver()

        let event = await firstEvent(
            of: observer,
            whilePosting: NSWorkspace.didWakeNotification,
            on: NSWorkspace.shared.notificationCenter,
            within: 2
        )

        #expect(event == .didWake)
    }

    @Test("o mesmo aviso no centro padrão não chega, e o silêncio seria o sintoma")
    func theSameNotificationOnTheDefaultCenterNeverArrives() async {
        let observer = WorkspacePowerEventObserver()

        let event = await firstEvent(
            of: observer,
            whilePosting: NSWorkspace.didWakeNotification,
            on: NotificationCenter.default,
            within: 0.4
        )

        #expect(event == nil)
    }

    @Test("a atividade da sonda não impede a máquina de dormir")
    func probeActivityStillAllowsIdleSystemSleep() {
        #expect(ProcessActivityAsserter.options == .userInitiatedAllowingIdleSystemSleep)
        #expect(ProcessActivityAsserter.options.contains(.idleSystemSleepDisabled) == false)
    }

    @Test("a atividade da sonda é declarada e encerrada no processo real")
    func probeActivityBeginsAndEndsOnTheRealProcess() {
        let asserter = ProcessActivityAsserter()

        let assertion = asserter.beginProbeActivity()
        assertion.end()
    }
}
