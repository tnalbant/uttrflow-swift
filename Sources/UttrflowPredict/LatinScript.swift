import UttrflowCore

/// Whether text is written in the Latin alphabet, which is the only script a suggestion may write. See `Docs/predict.md`.
public enum LatinScript {
    /// Whether no letter, mark or digit in the text belongs to a script other than Latin; symbols, emoji and spaces never count.
    public static func writes(_ text: some StringProtocol) -> Bool {
        !text.unicodeScalars.contains(where: isForeign)
    }

    /// Whether the scalar is a letter, mark or digit of another script.
    static func isForeign(_ scalar: Unicode.Scalar) -> Bool {
        guard scalar.value >= 0x80 else { return false }
        let properties = scalar.properties
        let writing: Bool
        switch properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark, .decimalNumber, .letterNumber, .otherNumber:
            writing = true
        default:
            writing = properties.isAlphabetic
        }
        return writing && !UttrflowCore.LatinScript.isInLatinRange(scalar)
    }
}

/// Whether a suggestion can be shown and inserted without hidden or terminal-active scalars.
public enum SuggestionTextSafety {
    /// Rejects control and format scalars and the replacement character without rewriting the candidate.
    public static func allows(_ text: some StringProtocol) -> Bool {
        !text.unicodeScalars.contains { scalar in
            let category = scalar.properties.generalCategory
            return category == .control || category == .format || scalar.value == 0xFFFD
        }
    }
}
