import Testing

@testable import UttrflowCore

@Suite("Unicode text matching")
struct TextMatchingTests {
    @Test("Case folding handles expansions and canonical equivalents")
    func caseFoldedKey() {
        #expect(TextMatching.caseFoldedKey("Straße") == TextMatching.caseFoldedKey("STRASSE"))
        #expect(TextMatching.caseFoldedKey("é") == TextMatching.caseFoldedKey("e\u{301}"))
        #expect(TextMatching.caseFoldedKey("İ") == TextMatching.caseFoldedKey("i\u{307}"))
        #expect(TextMatching.caseFoldedKey("İ") != TextMatching.caseFoldedKey("i"))
    }
}
