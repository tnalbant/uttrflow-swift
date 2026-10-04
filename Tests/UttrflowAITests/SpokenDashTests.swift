import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("Spoken dash in technical destinations", .bug(id: 2502))
struct SpokenDashTests {
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

    @Test("keeps a prose dash an em dash when a command noun is elsewhere in the sentence")
    func keepsProseDashBesideCommandNouns() {
        for (spoken, expected) in [
            ("i merged the branch dash it fixes the bug", "i merged the branch — it fixes the bug"),
            ("the new branch dash we should delete it", "the new branch — we should delete it"),
            (
                "she is in command dash we think dash of the unit",
                "she is in command — we think — of the unit"
            ),
            ("the terminal dash so it seems dash is old", "the terminal — so it seems — is old"),
            ("the branch is fix dash login dash bug", "the branch is fix-login-bug"),
            ("git commit dash m fix the bug", "git commit -m fix the bug"),
        ] {
            let draft = Draft(text: spoken)
            #expect(SpokenPunctuationPass().apply(draft).text == expected)
        }
    }
}
