import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("A spoken address")
struct SpokenAddressTests {
    private let sut = SpokenPunctuationPass()

    @Test(
        "writes the address where the words spell one",
        arguments: [
            ("forward the logs to support at example.com", "forward the logs to support@example.com"),
            (
                "forward the logs to support at example dot com",
                "forward the logs to support@example.com"
            ),
            (
                "please send the contract to first.last at example.com by tonight",
                "please send the contract to first.last@example.com by tonight"
            ),
            (
                "please send the contract to priya dot shah at example dot com by tonight",
                "please send the contract to priya.shah@example.com by tonight"
            ),
            (
                "my work address is ops-team at mail.example.org",
                "my work address is ops-team@mail.example.org"
            ),
            (
                "my work address is ops-team at mail dot example dot org",
                "my work address is ops-team@mail.example.org"
            ),
            (
                "email me at sam at example dot com when it is ready",
                "email me at sam@example.com when it is ready"
            ),
            (
                "write to info at example dot com and billing at example dot net",
                "write to info@example.com and billing@example.net"
            ),
            ("contact support at example.com today", "contact support@example.com today"),
            ("cc billing at example dot com", "cc billing@example.com"),
        ]
    )
    func writesTheAddress(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    /// The sentence's own stop sits on the domain's last word, so the address keeps it and the words either side of it.
    @Test(
        "keeps the marks the address stood with",
        arguments: [
            (
                "my work address is ops-team at mail.example.org.",
                "my work address is ops-team@mail.example.org."
            ),
            ("send it to support at example dot com.", "send it to support@example.com."),
            (
                "write to info at example dot com, and billing at example dot net",
                "write to info@example.com, and billing@example.net"
            ),
        ]
    )
    func keepsItsMarks(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "leaves an ordinary at alone",
        arguments: [
            "look at example.com",
            "look at example.com when you have a minute",
            "i'll look at example.com",
            "we met at the office at five",
            "meet me at the office",
            "the docs are available at example.com",
            "the file is at example.com",
            "the invoice at example.com is wrong",
            "please send the report at example.com",
            "he works at Example dot com offices",
            "email me at example.com",
            "we are at 10.30 already",
            "send the invoice at 5 dot 30",
            "forward the logs to support, at example.com",
            "forward the logs to support at (example.com)",
            "it is just at the corner",
            "the car is parked at the airport",
            "it is not at all clear",
            "it is not at the front desk",
            "she is out at the shops",
            "the file is open at line ten",
            "the problem is right at the start",
        ]
    )
    func leavesOrdinaryAtAlone(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// A domain needs an ending the pass knows, because guessing at one is how ordinary prose is rewritten.
    @Test(
        "leaves a domain whose ending it does not know",
        arguments: [
            "forward the logs to support at example.wibble",
            "forward the logs to support at example dot wibble",
            "forward the logs to support at example",
        ]
    )
    func leavesAnUnknownEnding(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test(
        "writes dictated web addresses paths filenames and identifiers",
        arguments: [
            ("visit example dot com slash docs", "visit example.com/docs"),
            ("the site is www dot example dot com", "the site is www.example.com"),
            ("go to https colon slash slash example dot com", "go to https://example.com"),
            (
                "the docs live at docs dot example dot com slash api slash v two",
                "the docs live at docs.example.com/api/v2"
            ),
            ("open package dot json", "open package.json"),
            ("edit the dot env file", "edit the .env file"),
            ("the path is slash users slash sam slash notes", "the path is /users/sam/notes"),
            ("my handle is at sam underscore dev", "my handle is @sam_dev"),
            ("my handle is sam at discord", "my handle is sam@discord"),
            ("my handle is sam at example dot com", "my handle is sam@example.com"),
            ("the variable is user underscore id", "the variable is user_id"),
        ]
    )
    func writesSpokenAddresses(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "writes a label spoken with digits, an underscore, a hyphen or a plus tag",
        arguments: [
            ("email sam dot jones nine nine at example dot com", "email sam.jones99@example.com"),
            ("email sam dot jones 99 at example dot com", "email sam.jones99@example.com"),
            ("send it to team twenty one at example dot org", "send it to team21@example.org"),
            ("send it to sam underscore jones at example dot com", "send it to sam_jones@example.com"),
            ("email sam plus invoices at example dot com", "email sam+invoices@example.com"),
            ("email ops dash team at example dot com", "email ops-team@example.com"),
            ("email ops hyphen team at example dot net", "email ops-team@example.net"),
            ("email sam at my dash mail dot example dot com", "email sam@my-mail.example.com"),
            (
                "write to sam underscore lee two at mail dash box dot example dot org",
                "write to sam_lee2@mail-box.example.org"
            ),
            ("cc sam plus news underscore feed at example dot com", "cc sam+news_feed@example.com"),
            ("my handle is sam underscore jones at example dot com", "my handle is sam_jones@example.com"),
            ("email j dot doe two thousand at example dot com", "email j.doe2000@example.com"),
            (
                "forward it to build underscore bot at ci dash runner dot example dot net",
                "forward it to build_bot@ci-runner.example.net"
            ),
            (
                "contact help plus urgent at support dot example dot io",
                "contact help+urgent@support.example.io"
            ),
            ("email sam dot lee 2024 at example dot co dot uk", "email sam.lee2024@example.co.uk"),
        ]
    )
    func writesJoinedLabels(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "writes no address from prose that says a joiner or a number near at",
        arguments: [
            "plus the dash at the end",
            "the plus side at example dot com",
            "we met nine at example dot com",
            "it is plus two at the moment",
            "add a dash at the start",
            "she ran nine miles at dawn",
            "the score was five plus three at half time",
            "send the report at example dot com",
            "we met at nine at example dot com",
            "it went from plus to minus at the close",
            "type a dash at the prompt",
            "he scored twenty at the game",
        ]
    )
    func leavesJoinerProse(input: String) {
        #expect(!cleaned(input, by: sut).contains("@"))
    }

    @Test(
        "keeps ordinary dot and slash words",
        arguments: [
            "a dot on the map",
            "a slash in prices",
            "put a dot on the map",
            "there is a slash in prices",
        ]
    )
    func keepsOrdinaryWords(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// Nothing is announced across a sentence end, so an address's words must all sit in one sentence.
    @Test(
        "leaves words that straddle a sentence end",
        arguments: [
            "send it. support at example.com",
            "write to info at example dot com. And billing at example dot net",
        ]
    )
    func leavesWordsAcrossASentenceEnd(input: String) {
        let cleaned = cleaned(input, by: sut)
        #expect(cleaned.contains("at example.com") || cleaned.contains("at example dot net"))
    }

    @Test("records the address on the first word and the rest as removed")
    func provenance() {
        let draft = sut.apply(Draft(text: "cc billing at example dot com"))
        #expect(draft.words[1].state == .replaced(by: SpokenPunctuationPass.id, from: "billing"))
        #expect(draft.words[2].state == .removed(by: SpokenPunctuationPass.id))
        #expect(draft.words[4].state == .removed(by: SpokenPunctuationPass.id))
        #expect(draft.text == "cc billing@example.com")
    }

    /// The pass converts rather than deletes, so the words it dropped are covered by its own grant.
    @Test("leaves the meaning guard nothing to answer for")
    func removalsAreAuthorised() {
        let draft = sut.apply(Draft(text: "cc billing at example dot com"))
        #expect(RemovalAudit.unauthorised(in: draft, grants: CleaningPipeline.standard.grants).isEmpty)
        #expect(
            MeaningPreservationGuard().verdict(draft: draft, rewritten: "Cc billing@example.com.")
                == .accepted)
    }
}
