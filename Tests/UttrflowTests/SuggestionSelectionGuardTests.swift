import Foundation
import Testing
import UttrflowContext
import UttrflowPredict

@testable import Uttrflow

@Suite("AX selection changes while a suggestion is armed")
struct SuggestionSelectionGuardTests {
    @Test("a rotor-only caret move withdraws the offer without a key event")
    func rotorMoveWithdrawsOffer() {
        var guardrail = ArmedSelectionGuard(expectedRange: NSRange(location: 12, length: 0))
        let focusedField = FocusedFieldSelection(
            processIdentifier: 41, elementHash: 900, range: NSRange(location: 12, length: 0))
        var armedOffer: String? = "completion"

        let initialSelectionChanged = guardrail.observe(focusedField)
        #expect(!initialSelectionChanged)

        let rotorSelection = FocusedFieldSelection(
            processIdentifier: 41, elementHash: 900, range: NSRange(location: 28, length: 0))
        if guardrail.observe(rotorSelection) { armedOffer = nil }

        #expect(armedOffer == nil)
    }

    @Test("a focused field change withdraws even when the range is unchanged")
    func fieldChangeWithdrawsOffer() {
        var guardrail = ArmedSelectionGuard(expectedRange: NSRange(location: 12, length: 0))
        let initialSelectionChanged = guardrail.observe(
            FocusedFieldSelection(
                processIdentifier: 41, elementHash: 900, range: NSRange(location: 12, length: 0)))
        let focusedFieldChanged = guardrail.observe(
            FocusedFieldSelection(
                processIdentifier: 41, elementHash: 901, range: NSRange(location: 12, length: 0)))
        #expect(!initialSelectionChanged)
        #expect(focusedFieldChanged)
    }

    @Test("text typed through the ghost advances its expected caret")
    func typedTextAdvancesExpectedCaret() {
        var guardrail = ArmedSelectionGuard(expectedRange: NSRange(location: 12, length: 0))
        guardrail.typedThrough("é🐕")

        let selectionChanged = guardrail.observe(
            FocusedFieldSelection(
                processIdentifier: 41, elementHash: 900, range: NSRange(location: 15, length: 0)))
        #expect(!selectionChanged)
    }

    @Test("an unavailable AX selection fails closed")
    func unavailableSelectionWithdrawsOffer() {
        var guardrail = ArmedSelectionGuard(expectedRange: NSRange(location: 12, length: 0))
        let shouldWithdraw = guardrail.observe(nil)
        #expect(shouldWithdraw)
    }
}

private actor FakeFocusedSelectionReader {
    private var selection: FocusedFieldSelection?

    init(_ selection: FocusedFieldSelection?) {
        self.selection = selection
    }

    func read() -> FocusedFieldSelection? { selection }

    func move(to selection: FocusedFieldSelection?) {
        self.selection = selection
    }
}

@MainActor
@Suite("Coordinator AX selection polling")
struct SuggestionCoordinatorSelectionPollingTests {
    @Test("a rotor-only selection change withdraws the armed offer without an NSEvent")
    func rotorChangeWithdrawsArmedOffer() async throws {
        let focused = FocusedFieldSelection(
            processIdentifier: 41, elementHash: 900, range: NSRange(location: 12, length: 0))
        let reader = FakeFocusedSelectionReader(focused)
        let container = FileManager.default.temporaryDirectory
            .appending(path: "uttrflow-2648-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let coordinator = try SuggestionCoordinator(
            container: container, preferences: SuggestionPreferences(isEnabled: true),
            focusedSelectionReader: { await reader.read() })
        defer {
            coordinator.stop()
            try? FileManager.default.removeItem(at: container)
        }
        coordinator.armSelectionMonitor(for: .certain("completion"), at: focused.range)

        await coordinator.pollFocusedSelection()
        #expect(coordinator.armedOffer == "completion")

        await reader.move(
            to: FocusedFieldSelection(
                processIdentifier: 41, elementHash: 900, range: NSRange(location: 28, length: 0)))
        await coordinator.pollFocusedSelection()

        #expect(coordinator.armedOffer == nil)
    }
}
