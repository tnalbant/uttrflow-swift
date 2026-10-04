import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("AcronymCasingPass")
struct AcronymCasingPassTests {
    private let rules = CleaningPipeline.message(for: .standard(for: .plain), situation: .unknown)

    @Test(
        "writes an acronym said as one word in the lexicon's casing on the rules path",
        arguments: [
            ("the api returns json", "The API returns JSON."),
            ("api keys go in the sdk", "API keys go in the SDK."),
            ("we wrote three apis and two sdks", "We wrote three APIs and two SDKs."),
            ("the url, then the html.", "The URL, then the HTML."),
            ("store it as saas data in sql", "Store it as SaaS data in SQL."),
        ])
    func cased(input: String, expected: String) {
        #expect(rules.run(Draft(text: input)).text == expected)
    }

    @Test(
        "leaves a common word that equals an acronym spelled lower case",
        arguments: [
            ("give it to us", "Give it to us."),
            ("the it team will rest", "The it team will rest."),
            ("add more ram to the arm", "Add more ram to the arm."),
        ])
    func ordinaryKept(input: String, expected: String) {
        #expect(rules.run(Draft(text: input)).text == expected)
    }

    @Test("keeps a word written with its own casing")
    func ownCasingKept() {
        #expect(AcronymCasingPass().apply(Draft(text: "the aPi")).text == "the aPi")
        #expect(AcronymCasingPass().apply(Draft(text: "Api first")).text == "API first")
    }

    @Test("takes casing from the dictionary and from acronyms written on screen")
    func dictionaryAndScreen() {
        let pass = AcronymCasingPass(vocabulary: ["KPIx", "Zorbix"], onScreen: ["Ship the OKRz soon"])
        #expect(
            pass.apply(Draft(text: "the kpix and okrz for zorbix")).text == "the KPIx and OKRz for zorbix")
    }

    @Test("reads only the acronyms that apply where the words are going")
    func destination() {
        #expect(AcronymCasingPass(destination: .terminal).forms["api"] == "API")
        #expect(AcronymCasingPass().forms["go"] == nil)
    }
}
