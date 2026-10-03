import Testing
import UttrflowCore

@testable import UttrflowAI
@testable import UttrflowPipeline

/// One dictation spoken over several pieces, each as the recogniser stopped it, and the message it must become.
struct MultiPieceCase: Sendable, CustomTestStringConvertible {
    let id: String
    let pieces: [String]
    let context: AppContext
    let destination: Destination
    let expected: String

    var testDescription: String { id }
}

@Suite("Multi-piece corpus: whole-message decisions are made once, of the joined text")
struct MultiPieceCorpusTests {
    private let router = TransformerRouter(engines: [RuleBasedTransformer()], preference: [.rules])

    private static let chat = AppContext.fixture(
        applicationName: "Messages", bundleIdentifier: "com.apple.MobileSMS")
    private static let document = AppContext.fixture(
        applicationName: "TextEdit", bundleIdentifier: "com.apple.TextEdit", documentName: "Notes")
    private static let midSentence = AppContext.fixture(
        applicationName: "TextEdit", bundleIdentifier: "com.apple.TextEdit", documentName: "Notes",
        precedingText: "The report says that ")

    static let cases: [MultiPieceCase] = [
        MultiPieceCase(
            id: "chat-two-pieces-short-message-no-stop", pieces: ["on my way.", "be there soon."],
            context: chat, destination: .messaging, expected: "On my way. Be there soon"),
        MultiPieceCase(
            id: "chat-three-pieces-long-message-takes-stop",
            pieces: ["i left the office.", "the traffic is bad.", "i will be late"],
            context: chat, destination: .messaging,
            expected: "I left the office. The traffic is bad. I will be late."),
        MultiPieceCase(
            id: "document-two-pieces-one-final-stop", pieces: ["the build failed", "on the release branch."],
            context: document, destination: .document, expected: "The build failed on the release branch."),
        MultiPieceCase(
            id: "mid-sentence-caret-lowers-only-the-first-piece",
            pieces: ["the deployment timed out.", "we restarted it."],
            context: midSentence, destination: .document,
            expected: "the deployment timed out. We restarted it."),
    ]

    @Test("each case comes out as the whole message it is", arguments: cases)
    func joinedMessage(_ testCase: MultiPieceCase) async throws {
        #expect(try await dictate(testCase) == testCase.expected)
    }

    /// Cleans each piece at piece scope, joins them, and finishes the message once, as the pipeline does.
    private func dictate(_ testCase: MultiPieceCase) async throws -> String {
        let situation = Situation(
            app: testCase.context, insertion: testCase.context.insertionPoint,
            destination: testCase.destination)
        let formatter = DestinationFormatter.standard(for: situation)
        var pieces: [Piece] = []
        for part in testCase.pieces {
            let heard = Transcription(
                text: part, detectedLanguage: DetectedLanguage(code: .english, confidence: 1))
            let cleaned = try await router.clean(
                TransformationRequest(transcription: heard, situation: situation, scope: .piece))
            pieces.append(Piece(heard: heard, corrected: .unchanged(part), cleaned: cleaned))
        }
        let joined = PieceJoiner.join(pieces, under: formatter)
        return await router.finishMessage(
            joined.cleaned.text,
            for: TransformationRequest(transcription: joined.heard, situation: situation))
    }
}
