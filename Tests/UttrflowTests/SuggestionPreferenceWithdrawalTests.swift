import Foundation
import Testing
import UttrflowPredict

@testable import Uttrflow

@MainActor
@Suite("Suggestion preferences withdraw work that is no longer allowed")
struct SuggestionPreferenceWithdrawalTests {
    @Test("Disabling suggestions for the frontmost application invalidates the current session")
    func disablingTheFrontmostApplicationInvalidatesTheSession() {
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        let before = SuggestionPreferences(isEnabled: true)
        var appDisabled = before
        appDisabled.set("com.example.editor", isOn: false)
        #expect(
            SuggestionCoordinator.disablesSuggestions(
                in: "com.example.editor", before: before, after: appDisabled, at: moment))

        var otherAppDisabled = before
        otherAppDisabled.set("com.example.other", isOn: false)
        #expect(
            !SuggestionCoordinator.disablesSuggestions(
                in: "com.example.editor", before: before, after: otherAppDisabled, at: moment))
        #expect(
            !SuggestionCoordinator.disablesSuggestions(
                in: "com.example.editor", before: before, after: before, at: moment))
    }

    @Test("Pausing suggestions withdraws for every frontmost application")
    func pausingDisablesSuggestions() {
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        let before = SuggestionPreferences(isEnabled: true)
        var paused = before
        paused.setPaused(true, at: moment)
        #expect(
            SuggestionCoordinator.disablesSuggestions(
                in: "com.example.editor", before: before, after: paused, at: moment))
        #expect(
            SuggestionCoordinator.disablesSuggestions(
                in: nil, before: before, after: SuggestionPreferences(isEnabled: false), at: moment))
    }
}
