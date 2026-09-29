import AppKit
import Foundation
import Testing
import UttrflowContext
import UttrflowPredict

@testable import Uttrflow

@MainActor
private final class FakeFocusedFieldValueObserver: FocusedFieldValueObserving {
    private var onValueChanged: (@MainActor () -> Void)?
    private var onNativeMenuVisibilityChanged: (@MainActor (Bool) -> Void)?

    func start(
        onValueChanged: @escaping @MainActor () -> Void,
        onNativeMenuVisibilityChanged: @escaping @MainActor (Bool) -> Void
    ) {
        self.onValueChanged = onValueChanged
        self.onNativeMenuVisibilityChanged = onNativeMenuVisibilityChanged
    }

    func refresh() {}
    func stop() {
        onValueChanged = nil
        onNativeMenuVisibilityChanged = nil
    }
    func simulateAXValueChange() { onValueChanged?() }
    func simulateNativeMenuOpened() { onNativeMenuVisibilityChanged?(true) }
}

@MainActor
@Suite("AX value changes withdraw stale suggestion offers", .serialized)
struct FocusedFieldValueObserverTests {
    @Test("an AX SetValue change disarms and hides the current offer")
    func axValueChangeWithdrawsTheOffer() throws {
        let container = FileManager.default.temporaryDirectory.appending(
            path: "ax-value-change-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let observer = FakeFocusedFieldValueObserver()
        let coordinator = try SuggestionCoordinator(
            container: container, preferences: SuggestionPreferences(isEnabled: true),
            focusedFieldValueObserver: observer)
        let panel = SuggestionPanelController.shared
        defer {
            coordinator.stop()
            panel.hide()
        }

        let screen = try #require(NSScreen.screens.first).visibleFrame
        let caret = CGRect(x: screen.minX + 200, y: screen.midY, width: 0, height: 17)
        let field = CGRect(x: screen.minX + 100, y: screen.midY - 10, width: 500, height: 24)
        let snapshot = FocusedFieldSnapshot(
            bundleIdentifier: "com.example.editor", applicationName: "Editor", role: "AXTextField",
            value: "meet", selection: NSRange(location: 4, length: 0), caret: caret,
            window: screen, field: field)

        coordinator.draw(
            SuggestionUpdate(suggestion: .certain("meet later"), armed: .tab, silence: nil),
            in: snapshot)
        #expect(coordinator.armedOffer == "meet later")
        #expect(panel.isShowing)

        coordinator.watchFocusedFieldValues()
        observer.simulateAXValueChange()

        #expect(coordinator.armedOffer == nil)
        #expect(!panel.isShowing)
    }

    @Test("an AX menu opening withdraws the offer before its Tab gesture")
    func axMenuOpeningWithdrawsTheOffer() throws {
        let container = FileManager.default.temporaryDirectory.appending(
            path: "ax-menu-open-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let observer = FakeFocusedFieldValueObserver()
        let coordinator = try SuggestionCoordinator(
            container: container, preferences: SuggestionPreferences(isEnabled: true),
            focusedFieldValueObserver: observer)
        let panel = SuggestionPanelController.shared
        defer {
            coordinator.stop()
            panel.hide()
        }

        let screen = try #require(NSScreen.screens.first).visibleFrame
        let caret = CGRect(x: screen.minX + 200, y: screen.midY, width: 0, height: 17)
        let field = CGRect(x: screen.minX + 100, y: screen.midY - 10, width: 500, height: 24)
        let snapshot = FocusedFieldSnapshot(
            bundleIdentifier: "com.example.editor", applicationName: "Editor", role: "AXTextField",
            value: "meet", selection: NSRange(location: 4, length: 0), caret: caret,
            window: screen, field: field)

        coordinator.draw(
            SuggestionUpdate(suggestion: .certain("meet later"), armed: .tab, silence: nil),
            in: snapshot)
        coordinator.watchFocusedFieldValues()
        observer.simulateNativeMenuOpened()

        #expect(coordinator.armedOffer == nil)
        #expect(!panel.isShowing)
    }
}
