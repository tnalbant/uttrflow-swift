import NaturalLanguage

/// Whether one word can stand in another's place in a sentence, judged by the word class each takes in that place.
public enum WordSlot {
    /// Words that open an utterance of their own, so a correction never takes one as the word it replaces with.
    public static let utteranceOpeners: Set<String> = Restatement.answerHeads.union(["please"])

    /// Whether the first of `following` takes the word class `replaced` has after `lead`, so it can replace that word.
    public static func fits(
        replacing replaced: String, after lead: [String], with following: [String]
    ) -> Bool {
        guard let replacement = following.first, !utteranceOpeners.contains(replacement) else { return false }
        guard let original = wordClass(at: lead.count, in: lead + [replaced] + following.dropFirst()),
            let candidate = wordClass(at: lead.count, in: lead + following)
        else { return false }
        return original == candidate
    }

    /// The lexical class the tagger gives the word at `index` when the words are read as one sentence.
    static func wordClass(at index: Int, in words: [String]) -> NLTag? {
        guard words.indices.contains(index) else { return nil }
        let text = words.joined(separator: " ")
        let offset = words[..<index].reduce(0) { $0 + $1.count + 1 }
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        let position = text.index(text.startIndex, offsetBy: offset)
        return tagger.tag(at: position, unit: .word, scheme: .lexicalClass).0
    }
}
