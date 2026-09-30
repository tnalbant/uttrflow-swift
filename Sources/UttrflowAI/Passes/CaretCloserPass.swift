public import UttrflowCore

/// Removes closing delimiters the model inferred from an opener before the caret, not from the dictation.
public struct CaretCloserPass: CleaningPass {
    public static let id: PassID = "caretCloser"

    public let precedingText: String?
    /// The piece after its ordinary cleaning passes, before the model rewrites it.
    public let spokenText: String?

    public init(precedingText: String? = nil, spokenText: String? = nil) {
        self.precedingText = precedingText
        self.spokenText = spokenText
    }

    public func apply(_ draft: Draft) -> Draft {
        guard let precedingText, Self.hasUnclosedOpeningDelimiter(precedingText),
            let index = draft.presentIndices.last(where: { !draft.words[$0].isLayoutMark })
        else { return draft }

        let spokenClosers = Self.closers(atEndOf: spokenText ?? "")
        var remainingSpokenClosers = spokenClosers
        let original = draft.words[index].text
        let shape = WordShape(original)
        let delimiterRun = shape.core.isEmpty ? shape.prefix + shape.suffix : shape.suffix
        var suffix = ""
        for character in delimiterRun {
            guard Self.closingDelimiters.contains(character) else {
                suffix.append(character)
                continue
            }
            if let count = remainingSpokenClosers[character], count > 0 {
                if count == 1 {
                    remainingSpokenClosers.removeValue(forKey: character)
                } else {
                    remainingSpokenClosers[character] = count - 1
                }
                suffix.append(character)
            }
        }
        guard suffix != delimiterRun else { return draft }

        var draft = draft
        let replacement = shape.core.isEmpty ? suffix : shape.prefix + shape.core + suffix
        if replacement.isEmpty {
            draft.remove(at: index, by: Self.id)
        } else {
            draft.replace(at: index, with: replacement, by: Self.id)
        }
        return draft
    }

    /// Whether text before the caret ends with any opener that has not been balanced there.
    static func hasUnclosedOpeningDelimiter(_ text: String) -> Bool {
        var brackets: [Character] = []
        var doubleQuoteIsOpen = false
        var singleQuoteIsOpen = false
        var curlyDoubleQuoteIsOpen = false
        var curlySingleQuoteIsOpen = false
        var guillemetIsOpen = false
        let characters = Array(text)
        var precedingBackslashes = 0

        for (offset, character) in characters.enumerated() {
            let previous = offset > 0 ? characters[offset - 1] : nil
            let next = offset + 1 < characters.count ? characters[offset + 1] : nil
            switch character {
            case "(": brackets.append(")")
            case "[": brackets.append("]")
            case "{": brackets.append("}")
            case ")", "]", "}":
                if brackets.last == character { brackets.removeLast() }
            case "\"" where precedingBackslashes.isMultiple(of: 2):
                doubleQuoteIsOpen.toggle()
            case "'" where precedingBackslashes.isMultiple(of: 2):
                // Apostrophes inside words are not quote delimiters.
                if !(previous?.isLetter == true && next?.isLetter == true) {
                    singleQuoteIsOpen.toggle()
                }
            case "\u{201C}": curlyDoubleQuoteIsOpen = true
            case "\u{201D}": curlyDoubleQuoteIsOpen = false
            case "\u{2018}": curlySingleQuoteIsOpen = true
            case "\u{2019}":
                if !(previous?.isLetter == true && next?.isLetter == true) {
                    curlySingleQuoteIsOpen = false
                }
            case "\u{00AB}": guillemetIsOpen = true
            case "\u{00BB}": guillemetIsOpen = false
            default: break
            }
            precedingBackslashes = character == "\\" ? precedingBackslashes + 1 : 0
        }
        return !brackets.isEmpty || doubleQuoteIsOpen || singleQuoteIsOpen
            || curlyDoubleQuoteIsOpen || curlySingleQuoteIsOpen || guillemetIsOpen
    }

    /// Counts closing delimiters carried by the last spoken token, so a dictated close is never removed.
    private static func closers(atEndOf text: String) -> [Character: Int] {
        guard let last = text.split(whereSeparator: \.isWhitespace).last else { return [:] }
        let shape = WordShape(String(last))
        let delimiterRun = shape.core.isEmpty ? shape.prefix + shape.suffix : shape.suffix
        return delimiterRun.reduce(into: [:]) { counts, character in
            guard closingDelimiters.contains(character) else { return }
            counts[character, default: 0] += 1
        }
    }

    private static let closingDelimiters: Set<Character> = [
        ")", "]", "}", "\"", "'", "\u{201D}", "\u{2019}", "\u{00BB}",
    ]
}
