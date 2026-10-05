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
            pass.apply(Draft(text: "the kpix and okrz for zorbix")).text == "the KPIx and OKRz for Zorbix")
    }

    @Test(
        "writes a tool or language name in the lexicon's casing on the rules path",
        arguments: [
            ("we deploy on kubernetes with postgresql", "We deploy on Kubernetes with PostgreSQL."),
            ("port the javascript to typescript", "Port the JavaScript to TypeScript."),
            ("install numpy on linux", "Install NumPy on Linux."),
        ])
    func namedTools(input: String, expected: String) {
        #expect(rules.run(Draft(text: input)).text == expected)
    }

    @Test("leaves an ordinary word that a lexicon name is spelled like")
    func ordinaryNameKept() {
        #expect(rules.run(Draft(text: "let it go now")).text == "Let it go now.")
    }

    @Test("lets the user's dictionary spelling beat the lexicon's, at a sentence start too")
    func dictionaryBeatsLexicon() {
        let pass = AcronymCasingPass(vocabulary: ["postgresql"])
        #expect(pass.forms["postgresql"] == "postgresql")
        let pipeline = CleaningPipeline.message(
            for: .standard(for: .plain), situation: .unknown, vocabulary: ["postgresql"])
        #expect(pipeline.run(Draft(text: "postgresql is up")).text == "postgresql is up.")
    }

    @Test("keeps a lexicon name written in lower case at a sentence start")
    func lowerCaseNameAtStart() {
        #expect(AcronymCasingPass().lowerCaseForms["ripgrep"] == "ripgrep")
        #expect(rules.run(Draft(text: "it failed. ripgrep found it")).text == "It failed. ripgrep found it.")
    }

    @Test("reads only the acronyms that apply where the words are going")
    func destination() {
        #expect(AcronymCasingPass(destination: .terminal).forms["api"] == "API")
        #expect(AcronymCasingPass().forms["go"] == nil)
    }
}
