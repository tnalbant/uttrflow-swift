import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowTestSupport

/// Issue 2354: a closing spoken period follows a pronoun subject, while a noun phrase keeps its word.
@Suite("Issue2354")
struct Issue2354ReproductionTests {
    private let cases: [(spoken: String, draft: String, expected: String)] = [
        ("that is it period", "that is it.", "That is it."),
        ("this is final period", "this is final.", "This is final."),
        ("during the trial period", "during the trial period", "During the trial period."),
        ("that trial period", "that trial period", "That trial period."),
        ("this period of time", "this period of time", "This period of time."),
    ]

    private func request(_ text: String) -> TransformationRequest {
        TransformationRequest(transcription: .fixture(text: text, language: .english))
    }

    @Test("the rules engine converts only the closing period")
    func rulesConvertTheClosingPeriod() async throws {
        for testCase in cases {
            #expect(
                try await RuleBasedTransformer().transform(request(testCase.spoken)).text == testCase.expected
            )
        }
    }

    @Test("the generative engine receives the same corrected draft before rewriting")
    func generativeEngineReceivesTheCorrectedDraft() async throws {
        for testCase in cases {
            let rewritten = testCase.expected.lowercased()
            let model = FakeCleanupModel { _ in
                rewritten.prefix(1).uppercased() + rewritten.dropFirst()
            }
            let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)

            #expect(try await sut.transform(request(testCase.spoken)).text == testCase.expected)
            #expect(model.calls.first?.text == "Spoken: \"\(testCase.draft)\"")
        }
    }
}
