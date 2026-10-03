import Testing

@testable import UttrflowAI

/// Whether two spellings are one word, asked of the single home for that question.
@Suite("WordForms")
struct WordFormsTests {
    @Test("Same-form comparison uses Unicode case folding and canonical composition")
    func unicodeEquivalentSpellings() {
        #expect(WordForms.sameForm("Straße", "STRASSE"))
        #expect(WordForms.sameForm("İstanbul", "i\u{307}STANBUL"))
        #expect(WordForms.sameForm("café", "cafe\u{301}"))
        #expect(!WordForms.sameForm("İstanbul", "istanbul"))
    }

    @Test("refuses unrelated irregular verbs and a longer word that only starts the same")
    func refusesUnrelatedForms() {
        #expect(!WordForms.sameForm("wrote", "spoken"))
        #expect(!WordForms.sameForm("wrote", "writeup"))
    }

    @Test("accepts common romanised Hindi respellings when asked to")
    func acceptsRomanisedHindiRespellings() {
        for (first, second) in [
            ("hai", "he"), ("nahi", "nahin"), ("kar", "kr"), ("mein", "me"), ("yeh", "ye"),
        ] {
            #expect(
                WordForms.sameForm(
                    first, second, allowingRomanisedHindiSpellings: true))
        }
    }

    @Test("accepts a Hindi verb and its stem, and a listed irregular form, both ways")
    func acceptsHindiVerbForms() {
        #expect(WordForms.sameRomanisedForm("aa", "aata"))
        #expect(WordForms.sameRomanisedForm("aata", "aa"))
        #expect(WordForms.sameRomanisedForm("kha", "khila"))
        #expect(WordForms.sameRomanisedForm("khila", "kha"))
    }
}
