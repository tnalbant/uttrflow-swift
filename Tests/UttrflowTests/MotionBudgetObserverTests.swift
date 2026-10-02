// Tests for the observer that keeps the motion budget current.

import AppKit
import Foundation
import Testing
import UttrflowCore

@testable import Uttrflow

@MainActor
@Suite("Keeping the motion budget current")
struct MotionBudgetObserverTests {
    /// A budget the test changes by hand, standing in for the system.
    private final class Source {
        var budget = MotionBudget()
    }

    @Test("reads the budget when it is made")
    func readsAtStart() {
        let source = Source()
        source.budget = MotionBudget(reducesMotion: true)

        let observer = MotionBudgetObserver(read: { source.budget })

        #expect(observer.budget == MotionBudget(reducesMotion: true))
    }

    @Test("re-reads the budget on each notice that can change it", arguments: [0, 1, 2])
    func rereadsOnNotice(_ index: Int) {
        let source = Source()
        let observer = MotionBudgetObserver(read: { source.budget })
        let notice = MotionBudget.changeNotices[index]
        source.budget = MotionBudget(energy: EnergyConditions(isLowPowerMode: true))

        notice.centre.post(name: notice.name, object: nil)

        #expect(observer.budget == source.budget)
    }

    @Test("keeps the same value when a refresh finds nothing changed")
    func refreshWithoutChange() {
        let source = Source()
        let observer = MotionBudgetObserver(read: { source.budget })

        observer.refresh()

        #expect(observer.budget == MotionBudget())
    }

    @Test("listens for power, thermal and Reduce Motion notices")
    func theNotices() {
        let names = MotionBudget.changeNotices.map(\.name)

        #expect(names.contains(.NSProcessInfoPowerStateDidChange))
        #expect(names.contains(ProcessInfo.thermalStateDidChangeNotification))
        #expect(names.contains(NSWorkspace.accessibilityDisplayOptionsDidChangeNotification))
        #expect(
            MotionBudget.changeNotices.last?.centre === NSWorkspace.shared.notificationCenter)
    }

    @Test("session loss, screen sleep, and system sleep each end dictation")
    func dictationSessionEndNotices() {
        let center = NotificationCenter()
        let received = Mutex(0)
        let observers = DictationSessionEndObserver.observe(in: center) {
            received.withLock { $0 += 1 }
        }
        defer { observers.forEach(center.removeObserver) }

        for notice in DictationSessionEndObserver.notices {
            center.post(name: notice, object: nil)
        }

        #expect(received.withLock { $0 } == 3)
    }

    @Test("a screen lock ends dictation")
    func screenLockEndsDictation() {
        let center = NotificationCenter()
        let received = Mutex(0)
        let observer = DictationSessionEndObserver.observeScreenLock(in: center) {
            received.withLock { $0 += 1 }
        }
        defer { center.removeObserver(observer) }

        center.post(name: DictationSessionEndObserver.screenIsLocked, object: nil)

        #expect(received.withLock { $0 } == 1)
    }

    @Test("shares one observer that starts from the system's reading")
    func sharedReadsTheSystem() {
        #expect(MotionBudgetObserver.shared.budget == MotionBudget.current())
    }
}
