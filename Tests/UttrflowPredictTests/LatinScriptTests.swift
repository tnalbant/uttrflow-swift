import Testing

@testable import UttrflowPredict

@Suite("Which script a suggestion may write")
struct LatinScriptTests {
    @Test(
        "The person's earlier lines in another script are not part of the situation a suggestion is written from."
    )
    func recentLinesKeepOnlyLatin() {
        let situation = GenerationSituation(
            application: "Chat", recentLines: ["haan bilkul", "नहीं जाना", "kal milte hain", "ok 你好"])
        #expect(situation.recentLines == ["haan bilkul", "kal milte hain"])
        #expect(situation.choosing(["a"]).recentLines == ["haan bilkul", "kal milte hain"])
    }
}
