import Testing
import UttrflowAI

@testable import UttrflowEval

@Suite("List caret corpus contract")
struct ListCaretCorpusTests {
    @Test(
        "requires a capital and no trailing stop when continuing an existing list item",
        arguments: [
            ("document-bullet-caret-capitalises", "The migration finished overnight"),
            ("document-numbered-caret-capitalises", "The rollback took 20 minutes"),
        ]
    )
    func keepsListItemEnding(id: String, expected: String) async throws {
        let testCase = try #require(EvaluationCorpus.all.first { $0.id == id })
        let result = try await RuleBasedTransformer().transform(testCase.transformationRequest())
        #expect(result.text == expected)
        let score = Scorer.score(result.text, against: testCase)
        #expect(score.passed)
        #expect(score.isExact)
        #expect(!Scorer.score(expected + ".", against: testCase).passed)
    }
}
