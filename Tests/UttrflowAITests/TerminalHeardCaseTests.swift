import Testing
import UttrflowCore

@testable import UttrflowAI

/// Issue #1923: in a terminal the first word of a dictated command must keep its heard case.
@Suite("A terminal keeps the heard case of a command's first word", .bug(id: 1923))
struct TerminalHeardCaseTests {
    private let terminal = AppContext(
        applicationName: "Terminal", bundleIdentifier: "com.apple.Terminal")
    private let codeEditor = AppContext(
        applicationName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode",
        documentName: "AppDelegate.swift")

    private func cleaned(_ spoken: String, into app: AppContext, vocabulary: [String] = []) -> String {
        let situation = SituationResolver.resolve(from: app)
        let formatter = DestinationFormatter.standard(for: situation.destination)
        return CleaningPipeline.standard(for: formatter, situation: situation, vocabulary: vocabulary)
            .run(Draft(text: spoken)).text
    }

    /// A terminal app resolves to the terminal destination rather than the code editor's.
    @Test("the terminal destination is reached from com.apple.Terminal")
    func terminalResolvesToTerminal() {
        let destination = SituationResolver.resolve(from: terminal).destination
        #expect(destination == .terminal)
    }

    /// A code editor still resolves to the code editor destination.
    @Test("the code editor destination is reached from Xcode")
    func codeEditorStillResolvesToCodeEditor() {
        let destination = SituationResolver.resolve(from: codeEditor).destination
        #expect(destination == .codeEditor)
    }

    /// The terminal formatter keeps the first word's heard case, since the shell is case-sensitive.
    @Test("the terminal formatter copies the first word's heard case")
    func terminalFormatterPolicy() {
        let formatter = DestinationFormatter.standard(for: .terminal)
        #expect(formatter.firstWord == .asSpoken)
        #expect(formatter.terminalStop == .never)
        #expect(formatter.layout == [.singleLine, .breaksAreSpaces])
        #expect(formatter.grammar == .asSpoken)
    }

    /// The exact cases the issue lists: every lower-case command stays lower-case.
    @Test("a dictated command keeps its case while spoken flags become literal")
    func terminalCommandsKeepTheirCase() {
        for (spoken, expected) in [
            ("ls dash la", "ls -la"), ("npm run build", "npm run build"),
            ("git commit dash m fix the login bug", "git commit -m fix the login bug"),
            ("cd documents slash projects", "cd documents slash projects"),
            ("docker compose up dash d", "docker compose up -d"),
        ] {
            #expect(cleaned(spoken, into: terminal) == expected)
        }
    }

    /// The case the speaker said is preserved through the deterministic pipeline, not just by the formatter.
    @Test("spoken short flags become literal in the rules path")
    func terminalKeepsCaseInTheRulesPath() {
        #expect(cleaned("ls dash la", into: terminal) == "ls -la")
        #expect(cleaned("npm run build", into: terminal) == "npm run build")
    }

    /// A code editor still capitalises the start of a sentence, so the fix has not over-corrected.
    @Test("a code editor keeps a code line's first word as spoken, since it may be a keyword")
    func codeEditorKeepsFirstWordAsSpoken() {
        #expect(cleaned("the build failed", into: codeEditor) == "the build failed")
        #expect(cleaned("function do thing", into: codeEditor) == "function do thing")
        #expect(
            cleaned("paymentsheet crashed again", into: codeEditor, vocabulary: ["PaymentSheet"])
                == "PaymentSheet crashed again")
    }

    /// A capitalised word mid-sentence in a code editor is left alone; a terminal never capitalises anyway.
    @Test("the code editor still mid-sentence lower-cases a first word at an unknown caret")
    func codeEditorMidSentenceLowercases() {
        let midway = AppContext(
            applicationName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode",
            documentName: "AppDelegate.swift",
            precedingText: "we ran the suite. then ")
        let situation = SituationResolver.resolve(from: midway)
        let formatter = DestinationFormatter.standard(for: situation.destination)
        let cleaned = CleaningPipeline.standard(for: formatter, situation: situation)
            .run(Draft(text: "the build failed")).text
        #expect(cleaned == "the build failed")
    }
}
