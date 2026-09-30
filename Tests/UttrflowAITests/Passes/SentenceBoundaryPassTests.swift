import Testing
import UttrflowAI
import UttrflowCore

@Suite("Sentence boundaries use the piece seam evidence inside a piece")
struct SentenceBoundaryPassTests {
    private func cleaned(_ text: String) -> String {
        CleaningPipeline.standard(
            for: .standard(for: .document), situation: .unknown
        ).run(Draft(text: text)).text
    }

    @Test(
        "repairs the reported in-piece false stops",
        arguments: [
            ("We need the. Final version of the contract", "We need the final version of the contract."),
            ("My manager. Wants the slides by noon", "My manager wants the slides by noon."),
            ("the server. crashed twice last night", "The server crashed twice last night."),
            ("I stayed home. Because it was raining", "I stayed home because it was raining."),
            ("I finished the report. And sent it to Maria", "I finished the report and sent it to Maria."),
            ("I wanted to come. But my train was cancelled", "I wanted to come, but my train was cancelled."),
            ("The shop was closed. So we went home", "The shop was closed, so we went home."),
            ("We can meet on Monday. Or on Tuesday", "We can meet on Monday or on Tuesday."),
        ])
    func repairsFalseStops(input: String, expected: String) {
        #expect(cleaned(input) == expected)
    }

    @Test("keeps a subject-bearing independent sentence after the stop")
    func keepsIndependentSentence() {
        #expect(cleaned("I left. She arrived") == "I left. She arrived.")
    }

    @Test("keeps a pronoun I and a known name capitalized when a false stop is removed")
    func keepsNameAndPronounCase() {
        #expect(
            cleaned("We finished the report. I sent it to Maria")
                == "We finished the report. I sent it to Maria.")
        #expect(cleaned("I sent it to. Paris yesterday") == "I sent it to Paris yesterday.")
        #expect(cleaned("We need the. Monday version") == "We need the Monday version.")
    }
}
