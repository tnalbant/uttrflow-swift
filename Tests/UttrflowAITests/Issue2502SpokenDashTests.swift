import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("Issue 2502 spoken dash in technical destinations")
struct Issue2502SpokenDashTests {
    @Test("writes long options and hyphenated names in terminals and editors")
    func writesTechnicalDashes() async throws {
        for destination in [Destination.terminal, .codeEditor, .sqlEditor, .document] {
            for (spoken, expected) in [
                ("Run npm install dash dash save dev", "Run npm install --save-dev"),
                ("Run git log dash dash oneline", "Run git log --oneline"),
                ("The branch is fix dash login dash bug", "The branch is fix-login-bug"),
                ("Git commit dash m fix the bug", "Git commit -m fix the bug"),
                ("Ls dash la", "Ls -la"),
            ] {
                let app = AppContext()
                let situation = Situation(app: app, insertion: app.insertionPoint, destination: destination)
                let request = TransformationRequest(
                    transcription: .fixture(text: spoken, language: .english), situation: situation)
                let result = try await RuleBasedTransformer().transform(request)
                #expect(result.text == expected)
            }
        }
    }

    @Test("keeps paired clause dashes as em dashes in prose")
    func keepsProseDash() async throws {
        let request = TransformationRequest(
            transcription: .fixture(
                text: "we went home dash it was late", language: .english))
        #expect(try await RuleBasedTransformer().transform(request).text == "We went home — it was late.")
    }
}
