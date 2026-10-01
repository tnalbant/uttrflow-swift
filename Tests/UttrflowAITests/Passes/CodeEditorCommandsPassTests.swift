import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("Spoken commands in code editors")
struct CodeEditorCommandsPassTests {
    @Test("writes the reported identifiers and empty parentheses")
    func acceptanceExamples() {
        let app = AppContext(
            applicationName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode",
            documentName: "Example.swift", precedingText: "let x = ")
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: .codeEditor)
        let pipeline = CleaningPipeline.beforeModel(
            for: .standard(for: .codeEditor), situation: situation)

        #expect(pipeline.run(Draft(text: "camel case user id")).text == "userId")
        #expect(pipeline.run(Draft(text: "snake case max retries")).text == "max_retries")
        #expect(pipeline.run(Draft(text: "open paren close paren")).text == "()")
    }

    @Test("keeps code commands through the deterministic transformer")
    func deterministicTransformer() async throws {
        let app = AppContext(
            applicationName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode",
            documentName: "Example.swift", precedingText: "let x = ")
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: .codeEditor)
        for (spoken, expected) in [
            ("camel case user id", "userId"),
            ("snake case max retries", "max_retries"),
            ("open paren close paren", "()"),
        ] {
            let request = TransformationRequest(
                transcription: Transcription(text: spoken), situation: situation)
            #expect(try await RuleBasedTransformer().transform(request).text == expected)
        }
    }

    @Test("stops identifier casing at a spoken clause mark")
    func clauseBoundary() {
        let app = AppContext(documentName: "Example.swift")
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: .codeEditor)
        let pipeline = CleaningPipeline.beforeModel(for: .standard(for: .codeEditor), situation: situation)
        #expect(
            pipeline.run(Draft(text: "camel case user id comma then explain it")).text
                == "userId, then explain it")
    }

    @Test("leaves command-like speech unchanged in comments and prose destinations")
    func scopeAndCommentControls() {
        let spoken = "camel case user id open paren close paren"
        let comment = AppContext(documentName: "Example.swift", precedingText: "// ")
        let commentSituation = Situation(
            app: comment, insertion: comment.insertionPoint, destination: .codeEditor)
        let commentPipeline = CleaningPipeline.beforeModel(
            for: .standard(for: .codeEditor), situation: commentSituation)
        #expect(commentPipeline.run(Draft(text: spoken)).text == spoken)

        for destination in [Destination.plain, .document, .email] {
            let app = AppContext(documentName: "Example.swift", precedingText: " ")
            let situation = Situation(app: app, insertion: app.insertionPoint, destination: destination)
            let pipeline = CleaningPipeline.beforeModel(
                for: .standard(for: destination), situation: situation)
            #expect(pipeline.run(Draft(text: spoken)).text == spoken)
        }
    }

    @Test("writes code operators")
    func symbols() {
        let app = AppContext(documentName: "Example.swift")
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: .codeEditor)
        let pipeline = CleaningPipeline.beforeModel(for: .standard(for: .codeEditor), situation: situation)
        #expect(pipeline.run(Draft(text: "max retries equals five")).text == "max retries = 5")
    }
}
