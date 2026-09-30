import Testing

@testable import Uttrflow

@MainActor
@Suite("Dictation Shortcuts")
struct ToggleDictationIntentTests {
    @Test("the Toggle Dictation intent invokes the registered controller action")
    func intentInvokesToggle() async throws {
        let previous = DictationIntentBridge.toggle
        var toggles = 0
        DictationIntentBridge.toggle = { toggles += 1 }
        defer { DictationIntentBridge.toggle = previous }

        _ = try await ToggleDictationIntent().perform()

        #expect(toggles == 1)
    }
}
