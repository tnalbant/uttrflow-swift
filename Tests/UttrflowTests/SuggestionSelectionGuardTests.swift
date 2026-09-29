import Foundation
import Testing
import UttrflowContext

@testable import Uttrflow

@Suite("AX selection changes while a suggestion is armed")
struct SuggestionSelectionGuardTests {
    @Test("a rotor-only caret move withdraws the offer without a key event")
    func rotorMoveWithdrawsOffer() {
        var guardrail = ArmedSelectionGuard(expectedRange: NSRange(location: 12, length: 0))
        let focusedField = FocusedFieldSelection(
            processIdentifier: 41, elementHash: 900, range: NSRange(location: 12, length: 0))
        var armedOffer: String? = "completion"

        #expect(!guardrail.observe(focusedField))

        let rotorSelection = FocusedFieldSelection(
            processIdentifier: 41, elementHash: 900, range: NSRange(location: 28, length: 0))
        if guardrail.observe(rotorSelection) { armedOffer = nil }

        #expect(armedOffer == nil)
    }

    @Test("a focused field change withdraws even when the range is unchanged")
    func fieldChangeWithdrawsOffer() {
        var guardrail = ArmedSelectionGuard(expectedRange: NSRange(location: 12, length: 0))
        #expect(
            !guardrail.observe(
                FocusedFieldSelection(
                    processIdentifier: 41, elementHash: 900, range: NSRange(location: 12, length: 0))))
        #expect(
            guardrail.observe(
                FocusedFieldSelection(
                    processIdentifier: 41, elementHash: 901, range: NSRange(location: 12, length: 0))))
    }

    @Test("text typed through the ghost advances its expected caret")
    func typedTextAdvancesExpectedCaret() {
        var guardrail = ArmedSelectionGuard(expectedRange: NSRange(location: 12, length: 0))
        guardrail.typedThrough("é🐕")

        #expect(
            !guardrail.observe(
                FocusedFieldSelection(
                    processIdentifier: 41, elementHash: 900, range: NSRange(location: 15, length: 0))))
    }

    @Test("an unavailable AX selection fails closed")
    func unavailableSelectionWithdrawsOffer() {
        var guardrail = ArmedSelectionGuard(expectedRange: NSRange(location: 12, length: 0))
        #expect(guardrail.observe(nil))
    }
}
