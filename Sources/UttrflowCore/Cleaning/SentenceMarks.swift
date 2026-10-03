/// The one home for the marks that end a sentence, in every script whose text may stand before the caret.
public enum SentenceMarks {
    /// Full stop, question and exclamation marks: Latin, danda and double danda, full-width, ideographic and Arabic.
    public static let ends: Set<Character> = [
        ".", "!", "?", "\u{0964}", "\u{0965}", "\u{3002}", "\u{FF0E}", "\u{FF01}", "\u{FF1F}", "\u{061F}",
        "\u{06D4}",
    ]

    /// The single-character ellipsis, which trails off rather than stops; each reader decides whether it ends a sentence.
    public static let ellipsis: Character = "\u{2026}"
}
