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
