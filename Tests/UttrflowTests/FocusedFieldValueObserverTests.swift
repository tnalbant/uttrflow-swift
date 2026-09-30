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
    @Test("closing one menu leaves the focused menu observed across a focus change")
    func menuVisibilitySurvivesFocusChange() {
        var state = NativeMenuVisibilityState<Int>()
        state.focusedElementChanged(to: 1)
        state.menuOpened(from: 100)
        state.menuOpened(from: 1)
        state.focusedElementChanged(to: 2)

        #expect(state.isOpen)
        #expect(state.observedFocusedElements == [1, 2])

        state.menuClosed(from: 100)
        #expect(state.isOpen)
        state.menuClosed(from: 1)

        #expect(!state.isOpen)
        #expect(state.observedFocusedElements == [2])
    }

    @Test("closing one of two menus from the same AX element keeps the other open")
    func multipleMenusFromOneElementStayOpenUntilBothClose() {
        var state = NativeMenuVisibilityState<Int>()
        state.menuOpened(from: 1)
        state.menuOpened(from: 1)

        state.menuClosed(from: 1)
        #expect(state.isOpen)

        state.menuClosed(from: 1)
        #expect(!state.isOpen)
    }

    @Test("observer teardown clears menu state and retained focused elements")
    func teardownClearsNativeMenuState() {
        var state = NativeMenuVisibilityState<Int>()
        state.focusedElementChanged(to: 1)
        state.menuOpened(from: 1)
        state.focusedElementChanged(to: 2)

        #expect(state.reset())
        #expect(!state.isOpen)
        #expect(state.observedFocusedElements.isEmpty)
    }

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
