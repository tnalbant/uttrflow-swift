import Testing

@testable import UttrflowClipboard

@Suite("E6 · making a note")
struct NotePromotionTests {
    @Test(
        "Swift line terminators become separate paragraphs",
        arguments: [
            "\u{000A}", "\u{000D}", "\u{000D}\u{000A}", "\u{000B}", "\u{000C}", "\u{2028}", "\u{2029}",
        ]
    )
    func lineTerminatorsBecomeParagraphs(_ separator: String) {
        #expect(NotePromotion.note(from: "before\(separator)after") == "<p>before</p><p>after</p>")
    }

    @Test("empty paragraphs and HTML escaping are preserved")
    func keepsEmptyParagraphsAndEscapesHTML() {
        #expect(NotePromotion.note(from: "\n\n") == "<p></p><p></p><p></p>")
        #expect(NotePromotion.note(from: "<a>&") == "<p>&lt;a&gt;&amp;</p>")
    }

    @Test("quotes are escaped and checkbox-looking text stays plain")
    func escapesQuotesAndKeepsCheckboxTextPlain() {
        #expect(
            NotePromotion.note(from: "[x] said \"don't <skip> & go\"")
                == "<p>[x] said &quot;don&#39;t &lt;skip&gt; &amp; go&quot;</p>"
        )
    }

    @Test("promoted text containing quotes reads back unchanged")
    func quotedTextRoundTripsThroughPlainText() {
        let original = "it's \"done\""
        let html = NotePromotion.note(from: original)

        #expect(html.contains("&#39;"))
        #expect(html.contains("&quot;"))
        #expect(RichTextPlainForm.plainText(fromHTML: html) == original)
    }
}
