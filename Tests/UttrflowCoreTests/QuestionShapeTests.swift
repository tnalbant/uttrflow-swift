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
            "what time is the meeting tomorrow", "how many people are coming",
            "what's the status of the release", "can you review the pull request", "did the build go green",
            "is anyone using the room", "do you have a minute", "have you seen the numbers",
            "Would you like some coffee", "it's a long weekend isn't it",
            "you know the answer don\u{2019}t you",
            "so did you finish the slides", "okay can we start the call", "I sent the file, did you get it",
            "did the tests pass should i merge it now",
            "is the meeting at ten or eleven do we need the projector",
            "where did you park the car i cannot find it anywhere",
            "what happens if the call fails", "what changed", "who owns the notification service",
            "are you around yet i should be there in ten",
            "the meeting is at three right", "you sent the invoice right", "the file is saved right",
            "we leave at noon right",
            "I'm blocked on the credentials for the sandbox account can someone help",
            "I think this will break if the array is empty can you add a check",
            "This duplicates the logic in the helper class can we reuse that instead",
            "I don't have access to the production database can someone grant it",
            "kya tum aa rahe ho", "kab tak ho jayega", "tum aa rahe ho kya",
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
            "have a great weekend", "tell me what you think", "that's right", "turn right at the station",
            "turn right", "you should turn right", "everything is right", "it feels right", "I have no right",
            "you got the answer right", "I think it is right",
            "if it rains, we stay in", "", "kya baat hai",
            "the printer is jammed again who used it last",
            "please close the door will you be home tonight",
        ])
    func leaves(text: String) {
        #expect(!QuestionShape.asks(shapes(text)))
    }
}
