// Tests for which of a system-wide and a per-application focused element a caller should keep.

import Testing

@testable import UttrflowCore

@Suite struct FocusedElementPreferenceTests {
    @Test func keepsSystemWideWhenItIsATextEntryRole() {
        let chosen = FocusedElementPreference.choose(
            systemWide: "system", systemWideRole: { _ in "AXTextField" },
            application: {
                Issue.record("the application must not be asked"); return "app"
            },
            applicationRole: { _ in "AXTextField" })
        #expect(chosen == "system")
    }

    /// The reported bug: a browser names the word under the caret system-wide, while its own editor is a text area.
    @Test func prefersTheApplicationWhenSystemWideNamesTheWordUnderTheCaret() {
        let chosen = FocusedElementPreference.choose(
            systemWide: "word", systemWideRole: { _ in "AXStaticText" },
            application: { "editor" }, applicationRole: { _ in "AXTextArea" })
        #expect(chosen == "editor")
    }

    @Test func fallsBackToSystemWideWhenNeitherRoleIsTextEntry() {
        let chosen = FocusedElementPreference.choose(
            systemWide: "group", systemWideRole: { _ in "AXGroup" },
            application: { "cell" }, applicationRole: { _ in "AXCell" })
        #expect(chosen == "group")
    }

    @Test func fallsBackToTheApplicationWhenSystemWideAnsweredNothing() {
        let chosen = FocusedElementPreference.choose(
            systemWide: String?.none, systemWideRole: { _ in nil },
            application: { "app" }, applicationRole: { _ in "AXGroup" })
        #expect(chosen == "app")
    }

    @Test func answersNothingWhenNeitherSideAnswered() {
        let chosen = FocusedElementPreference.choose(
            systemWide: String?.none, systemWideRole: { _ in nil },
            application: { nil }, applicationRole: { _ in nil })
        #expect(chosen == nil)
    }

    @Test func acceptsSystemWideOwnerWhenItMatchesTheRequestedApplication() {
        #expect(FocusedElementPreference.belongsToRequestedApplication(owner: 42, requested: 42, current: 7))
    }

    @Test func rejectsSystemWideOwnerWhenItBelongsToAnotherApplication() {
        #expect(!FocusedElementPreference.belongsToRequestedApplication(owner: 99, requested: 42, current: 7))
    }

    @Test func rejectsSystemWideOwnerWhenItIsTheCurrentProcessPanel() {
        #expect(!FocusedElementPreference.belongsToRequestedApplication(owner: 7, requested: 7, current: 7))
    }

    @Test func rejectsUnknownOwnershipSoTheApplicationLookupCanBeUsedAsFallback() {
        #expect(
            !FocusedElementPreference.belongsToRequestedApplication(owner: nil, requested: 42, current: 7))
        #expect(
            !FocusedElementPreference.belongsToRequestedApplication(owner: 42, requested: nil, current: 7))

        let chosen = FocusedElementPreference.choose(
            systemWide: Optional<String>.none, systemWideRole: { _ in nil },
            application: { "requested application" }, applicationRole: { _ in "AXTextField" })
        #expect(chosen == "requested application")
    }

    @Test func isTextEntryAcceptsEveryRoleAPersonTypesInto() {
        for role in ["AXTextArea", "AXTextField", "AXComboBox", "AXSearchField"] {
            #expect(FocusedElementPreference.isTextEntry(role))
        }
        #expect(!FocusedElementPreference.isTextEntry("AXWebArea"))
        #expect(!FocusedElementPreference.isTextEntry("AXStaticText"))
        #expect(!FocusedElementPreference.isTextEntry(nil))
    }
}
