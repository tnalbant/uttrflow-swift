public import NaturalLanguage

/// The one place a word's lexical class is read, so every seam decision agrees on what a word is.
public enum LexicalClass {
    /// The class the on-device tagger gives the word that starts at `position` in `text`.
    public static func tag(at position: String.Index, in text: String) -> NLTag? {
        guard position < text.endIndex else { return nil }
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        return tagger.tag(at: position, unit: .word, scheme: .lexicalClass).0
    }

    /// The class of the word at `index` when the words are read as one sentence.
    public static func tag(ofWordAt index: Int, in words: [String]) -> NLTag? {
        guard words.indices.contains(index) else { return nil }
        let text = words.joined(separator: " ")
        let offset = words[..<index].reduce(0) { $0 + $1.count + 1 }
        return tag(at: text.index(text.startIndex, offsetBy: offset), in: text)
    }

    /// Every word of `text` with its class, in order, skipping whitespace and punctuation.
    public static func tags(in text: String) -> [(word: String, tag: NLTag)] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        var result: [(word: String, tag: NLTag)] = []
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, range in
            if let tag { result.append((String(text[range]), tag)) }
            return true
        }
        return result
    }
}
