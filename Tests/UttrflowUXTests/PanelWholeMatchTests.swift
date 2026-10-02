// Tests for how the panel decides a clip's whole text is the query.
import Foundation
import Testing

@testable import UttrflowUX

@Suite("The quick panel: a clip whose whole text is the query")
struct PanelWholeMatchTests {
    let locale = PanelFixture.locale

    @Test(
        "matches the trimmed text ignoring case and accents",
        arguments: [
            ("invoice", "invoice", true),
            ("invoice", "  Invoice\n", true),
            ("cafe", "\tCAFÉ ", true),
            ("invoice", "invoice 42", false),
            ("invoice", "invoic", false),
            ("", "   \n", true),
            ("", "x", false),
            (" ", "   ", false),
            ("a b", " a b ", true),
        ])
    func matches(needle: String, text: String, expected: Bool) {
        #expect(PanelSnapshot.isWhole(needle, of: PanelFixture.clip(text), locale: locale) == expected)
    }

    @Test("rejects a long clip that only begins with the query")
    func longClip() {
        let text = "the " + String(repeating: "lorem ipsum dolor ", count: 50_000) + "\n"
        #expect(!PanelSnapshot.isWhole("the", of: PanelFixture.clip(text), locale: locale))
    }

    @Test("matches the text under typographic punctuation and whitespace folding")
    func foldedPunctuationAndWhitespace() {
        for (needle, text) in [
            ("don't", " don\u{2019}t "),
            ("a b", "a  b"),
            ("a-b", "a\u{2014}b"),
            ("a-b", "a\u{2013}b"),
        ] {
            #expect(PanelSnapshot.isWhole(needle, of: PanelFixture.clip(text), locale: locale))
        }
    }
}
