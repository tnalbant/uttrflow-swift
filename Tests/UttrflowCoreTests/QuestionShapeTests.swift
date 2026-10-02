import Testing

@testable import UttrflowCore

/// The words of `text` as the passes see them.
private func shapes(_ text: String) -> [WordShape] {
    text.split(separator: " ").map { WordShape(String($0)) }
}

@Suite("QuestionShape")
struct QuestionShapeTests {
    @Test(
        "reads a direct question from its word order",
        arguments: [
            "where did you put the keys", "which branch should I merge into",
            "what time is the meeting tomorrow", "what time is it", "how many people are coming",
            "how are you", "can you send it", "did you see the email", "is it ready",
            "what's the status of the release", "can you review the pull request", "did the build go green",
            "is anyone using the room", "do you have a minute", "have you seen the numbers",
            "Would you like some coffee", "it's a long weekend isn't it",
            "you know the answer don\u{2019}t you",
            "so did you finish the slides", "okay can we start the call", "I sent the file, did you get it",
            "did the tests pass should i merge it now",
            "papa did you take your medicine",
            "didi can you ask jiju if he's free on saturday",
            "hey quick question do we support ios sixteen or only seventeen and above",
            "is the meeting at ten or eleven do we need the projector",
            "where did you park the car i cannot find it anywhere",
            "what happens if the call fails", "what changed", "who owns the notification service",
            "the meeting is at three right", "you sent the invoice right", "the file is saved right",
            "we leave at noon right",
            "I'm blocked on the credentials for the sandbox account can someone help",
            "I think this will break if the array is empty can you add a check",
            "what I mean is we should wait",
            "This duplicates the logic in the helper class can we reuse that instead",
            "I don't have access to the production database can someone grant it",
            "kya tum aa rahe ho", "kab tak ho jayega", "tum aa rahe ho kya", "report bhej di kya",
            "report bhej diya kya", "report karoge kya", "kaunsa option better hai", "kaunsi file chahiye",
            "kaunse option sahi hain", "kya hua", "meeting kab hai", "tum kyun nahi aaye",
            "tum kal aa rahe ho na",
        ])
    func asks(text: String) {
        #expect(QuestionShape.asks(shapes(text)))
    }

    @Test(
        "leaves a statement, an indirect question and a command alone",
        arguments: [
            "I wonder if the build passed", "what we need is more time", "what we need is more tests",
            "what works for you is fine", "the person who owns the notification service is unclear",
            "where I put the keys is a mystery",
            "I don't know why the build failed", "when the build finishes we ship",
            "do the dishes before you leave",
            "papa did the shopping",
            "papa are you around yet i should be there in ten",
            "have a great weekend", "tell me what you think", "that's right", "turn right at the station",
            "turn right", "you should turn right", "everything is right", "it feels right", "I have no right",
            "you got the answer right", "I think it is right",
            "if it rains, we stay in", "", "kya baat hai", "sunno na ek baat",
            "woh kya hai na yaani mujhe time chahiye",
            "the printer is jammed again who used it last",
            "please close the door will you be home tonight",
            "are you around yet i should be there in ten",
        ])
    func leaves(text: String) {
        #expect(!QuestionShape.asks(shapes(text)))
    }

    @Test(
        "keeps reported content inside an inverted question",
        arguments: [
            "did she say that", "did she say we're late", "did she really say we're late",
            "did you know we lost", "did he say she was coming", "do you think we should wait",
            "can you tell me they arrived",
        ])
    func reportedContent(text: String) {
        #expect(QuestionShape.asks(shapes(text)))
    }

    @Test("leaves an unrelated declarative run-on unpunctuated")
    func unrelatedRunOn() {
        #expect(!QuestionShape.asks(shapes("are you around yet i should be there")))
    }

    @Test(
        "does not read a subject pronoun or demonstrative as an address",
        arguments: [
            "that is it", "it is a good idea", "this is a really good idea for us",
            "that was a good point", "it is my two cents", "i am a hundred percent sure",
            "these are a few good reasons", "those were a few good days", "we are a hundred percent sure",
            "he is a very good doctor", "she is a very good nurse", "they are a very good team",
            "it is good", "she is a nurse", "the report is a good idea", "it is not a good idea",
        ])
    func declarativePronounOpeners(text: String) {
        #expect(!QuestionShape.asks(shapes(text)))
        #expect(QuestionShape.leadingQuestionOpenerIndex(in: shapes(text)) == nil)
    }

    @Test("still reads a name before an inverted question as an address")
    func namedAddressOpensQuestion() {
        #expect(QuestionShape.asks(shapes("papa are you around")))
        #expect(QuestionShape.leadingQuestionOpenerIndex(in: shapes("papa are you around")) == 0)
    }

    @Test(
        "keeps dependent clauses inside an inverted question",
        arguments: [
            "is it okay if i leave at five", "is it fine if we start late", "is it okay when i call later",
        ])
    func dependentClauses(text: String) {
        #expect(QuestionShape.asks(shapes(text)))
    }
}
