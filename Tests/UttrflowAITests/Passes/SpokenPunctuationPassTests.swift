import Testing
import Foundation
import UttrflowCore

@testable import UttrflowAI

@Suite("SpokenPunctuationPass")
struct SpokenPunctuationPassTests {
    private let sut = SpokenPunctuationPass()

    @Test(
        "turns a mark said by name into the mark on the word before it",
        arguments: [
            ("add milk comma eggs comma and bread", "add milk, eggs, and bread"),
            ("is it ready question mark", "is it ready?"),
            ("ship it full stop", "ship it."),
            ("ship it period", "ship it."),
            ("that is it period", "that is it."),
            ("this is final period", "this is final."),
            ("wow exclamation mark", "wow!"),
            ("wow exclamation point", "wow!"),
            ("two things colon the milk", "two things: the milk"),
            ("milk semicolon eggs", "milk; eggs"),
            ("milk semi colon eggs", "milk; eggs"),
            ("ready. question mark", "ready?"),
            ("milk, comma eggs", "milk, eggs"),
            ("done comma we move on", "done, we move on"),
            ("call me tomorrow comma okay", "call me tomorrow, okay"),
            ("hi john comma how are you question mark", "hi john, how are you?"),
            ("here is the list colon apples and pears", "here is the list: apples and pears"),
            ("note colon bring snacks", "note: bring snacks"),
            ("meet at five colon thirty", "meet at five: 30"),
            ("the build passed period the tests passed period", "the build passed. the tests passed."),
            ("i finished the draft period", "i finished the draft."),
            ("that was amazing exclamation point", "that was amazing!"),
        ]
    )
    func attachesMarks(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "keeps abbreviation full stops when the standard pipeline adds a clause mark",
        arguments: [
            ("Is it 5 p.m. question mark", "Is it 5 p.m.?"),
            ("We left at 5 p.m. comma then ate.", "We left at 5 p.m., then ate."),
            ("Bring apples, pears, etc. exclamation mark", "Bring apples, pears, etc.!"),
            ("Meet at 5 p.m. exclamation mark", "Meet at 5 p.m.!"),
        ]
    )
    func keepsAbbreviationStops(input: String, expected: String) {
        #expect(CleaningPipeline.standard.run(Draft(text: input)).text == expected)
    }

    /// A two-word mark name cannot straddle a sentence end, because the halves were said in different sentences.
    @Test(
        "leaves a mark name whose two words sit in different sentences",
        arguments: [
            "She is full. Stop.",
            "the glass was full. Stop worrying about it",
            "ask the question. Mark it as done",
        ]
    )
    func leavesANameAcrossASentenceEnd(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// A noun phrase cannot begin in the sentence before, so a determiner there does not make the mark a mention.
    @Test(
        "takes a mark whose only determiner sits in the sentence before",
        arguments: [
            ("hand me a pen. Comma then go", "hand me a pen, then go"),
            ("hand me the red pen. Comma then go", "hand me the red pen, then go"),
            ("this is the plan. Full stop", "this is the plan."),
        ]
    )
    func takesAMarkWhoseDeterminerIsInTheSentenceBefore(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "ends a sentence with a spoken full stop only where the text closes",
        arguments: [
            ("ship it period new line next", "ship it. new line next"),
            ("ship it full stop new paragraph next", "ship it. new paragraph next"),
            ("he said open quote ship it period close quote", "he said \"ship it.\""),
            ("did you finish the trial period question mark", "did you finish the trial period?"),
            ("the trial period comma which ended", "the trial period, which ended"),
        ]
    )
    func fullStopsOnlyWhereTheTextCloses(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test("ends a sentence with a spoken full stop before a layout mark already placed")
    func fullStopBeforeLayoutMark() {
        let draft = Draft(words: ["ship", "it", "period", "\n", "next"].map { Draft.Word($0) })
        #expect(sut.apply(draft).text == "ship it.\nnext")
    }

    @Test("wraps the words between open quote and close quote")
    func quotes() {
        #expect(cleaned("he said open quote hello there close quote", by: sut) == "he said \"hello there\"")
    }

    @Test("joins the words around a hyphen, and spaces a dash")
    func hyphenAndDash() {
        #expect(cleaned("a well hyphen known bug", by: sut) == "a well-known bug")
        #expect(cleaned("we went home dash it was late", by: sut) == "we went home \u{2014} it was late")
    }

    /// "Dash" and "hyphen" are verbs too, and the particle after them is what says which was meant.
    @Test(
        "leaves dash and hyphen as words when a particle follows them",
        arguments: [
            "we should dash off a quick note to the client",
            "she had to dash out before the standup",
            "let me dash over to the other building",
            "hyphen in the name is fine",
        ]
    )
    func leavesTheVerb(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// An opening quote goes on the word after it, so a dictation may perfectly well begin with one.
    @Test(
        "wraps a quotation that opens the text",
        arguments: [
            (
                "open quote the build is green close quote that is what he said",
                "\"the build is green\" that is what he said"
            ),
            ("open quote ship it close quote", "\"ship it\""),
        ]
    )
    func wrapsAQuotationThatOpensTheText(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    /// The opening half still needs a word to go on, and the closing half still needs one before it.
    @Test(
        "leaves a half quotation with nothing to attach to as words",
        arguments: ["open quote", "close quote he said"])
    func leavesAHalfQuotation(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test(
        "leaves a mark that is mentioned rather than used",
        arguments: [
            "put a comma after the greeting",
            "the period of time",
            "add a period",
            "with no comma",
            "comma",
            "comma first",
            "a long period of time",
            "this period was hard",
            "these comma separated values are easy to read",
            "those question mark icons are confusing",
            "insert a colon",
            "say open quote",
            "a well hyphen",
            "the Dash app crashed",
            "a dash of salt",
        ]
    )
    func leavesMentions(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test("keeps words that mention mark names literally")
    func keepsLiteralVocabulary() {
        for input in [
            "the colon is an organ", "the period of time was long", "a new line of products",
            "question mark over his future", "a comma splice",
        ] {
            #expect(cleaned(input, by: sut) == input)
        }
    }

    /// "Period", "comma" and "dash" are nouns too, and a modifier hides the determiner that says so.
    @Test(
        "leaves the noun a determiner opens even when a modifier stands between them",
        arguments: [
            "during the trial period", "that trial period", "this period of time",
            "I love the Victorian period",
            "the 100 metre dash was close", "a short grace period follows",
        ]
    )
    func leavesTheHeadOfANounPhrase(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// The lookback stops at a mark name, so the phrase before one does not reach past it.
    @Test(
        "still converts a mark the speaker used, determiner or not",
        arguments: [
            ("ship it period", "ship it."),
            ("milk comma eggs comma and bread", "milk, eggs, and bread"),
            ("did you finish the trial period question mark", "did you finish the trial period?"),
        ]
    )
    func convertsWhatWasUsed(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    /// Issue 237: "comma", "colon" and "dash" are nouns that modify the word after them, so a mid-sentence one needs evidence.
    @Test(
        "leaves an everyday mark name with no evidence that it stands at a seam",
        arguments: [
            "suffering from colon cancer", "he has colon trouble again",
            "screened for colon cancer last year", "write comma separated values please",
            "reduce comma usage in prose", "sprint dash training starts monday",
            "we checked dash cam footage", "he keeps writing comma splices",
            "done comma next", "two things colon milk", "milk comma eggs and bread",
        ]
    )
    func leavesAnOrdinaryNameWithoutEvidence(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test(
        "takes an everyday mark name where the text closes, a mark precedes it, a small word follows, or it is said again",
        arguments: [
            ("the steps are as follows colon", "the steps are as follows:"),
            ("hi team comma", "hi team,"),
            ("hi team comma new line thanks", "hi team, new line thanks"),
            ("milk, comma eggs", "milk, eggs"),
            ("however comma the build passed", "however, the build passed"),
            ("the reason is simple colon we ran out", "the reason is simple: we ran out"),
            ("we left early dash it was raining", "we left early \u{2014} it was raining"),
            ("apples comma pears comma plums", "apples, pears, plums"),
            ("red comma green. blue comma white", "red comma green. blue comma white"),
            ("we have colon trouble. the colon comma and more", "we have colon trouble. the colon, and more"),
        ]
    )
    func takesAnOrdinaryNameOnEvidence(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "leaves a full stop or period that is not at the end, and a hyphen or dash that is",
        arguments: [
            "the trial period ended last week",
            "ship it period next thing",
            "done full stop next",
            "we made it home dash",
            "well hyphen new line known",
            "we went home dash new line late",
        ]
    )
    func leavesMisplacedMarks(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test("records the mark on the word before and the name as removed")
    func provenance() {
        let draft = sut.apply(Draft(text: "milk comma and eggs"))
        #expect(draft.words[0].state == .replaced(by: SpokenPunctuationPass.id, from: "milk"))
        #expect(draft.words[1].state == .removed(by: SpokenPunctuationPass.id))
        #expect(draft.words[2].state == .kept)
    }

    @Test("a long unpunctuated rules-only transcript finishes inside the rules budget")
    func longUnpunctuatedTranscript() async throws {
        let text = String(
            repeating: "so i was thinking about the garden and the tomatoes are growing well this year ",
            count: 200)
        let request = TransformationRequest(transcription: Transcription(text: text))
        let clock = ContinuousClock()
        let start = clock.now
        let result = try await RuleBasedTransformer().transform(request)
        #expect(clock.now - start < StageTimeout.rules)
        #expect(result.text.split(whereSeparator: \.isWhitespace).count == 2_801)
    }
}
