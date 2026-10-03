import Foundation
import Testing
import UttrflowPredict

@testable import Uttrflow

@MainActor
@Suite("Session end withdraws suggestions", .serialized)
struct SuggestionSessionEndTests {
    @Test("session resign, display sleep, system sleep and screen lock stop suggestion work")
    func notificationsStopSuggestionWork() async throws {
        let container = FileManager.default.temporaryDirectory
            .appending(path: "suggestion-session-end-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let workspaceCenter = NotificationCenter()
        let screenLockCenter = NotificationCenter()
        let coordinator = try SuggestionCoordinator(
            container: container, preferences: SuggestionPreferences(isEnabled: true))
        defer { coordinator.stop() }
        coordinator.observeSessionEnd(in: workspaceCenter, screenLockCenter: screenLockCenter)

        for notice in DictationSessionEndObserver.notices {
            coordinator.noteActivity()
            coordinator.armSelectionMonitor(for: .certain("completion"), at: NSRange(location: 12, length: 0))
            #expect(coordinator.isTickerScheduled)
            #expect(coordinator.isSelectionPolling)

            workspaceCenter.post(name: notice, object: nil)
            await Task.yield()

            #expect(coordinator.armedOffer == nil)
            #expect(!coordinator.isSelectionPolling)
            #expect(!coordinator.isTickerScheduled)
        }

        coordinator.noteActivity()
        coordinator.armSelectionMonitor(for: .certain("completion"), at: NSRange(location: 12, length: 0))
        screenLockCenter.post(name: DictationSessionEndObserver.screenIsLocked, object: nil)
        await Task.yield()

        #expect(coordinator.armedOffer == nil)
        #expect(!coordinator.isSelectionPolling)
        #expect(!coordinator.isTickerScheduled)
    }
}
