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
}
