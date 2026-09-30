/// What sits at the caret, so the first word can match what came before it.
public struct InsertionPoint: Sendable, Equatable, Codable {
    /// Where the caret stands in the sentence around it.
    public enum SentenceState: String, Sendable, Equatable, Codable {
        case startOfText
        case startOfSentence
        case midSentence
        /// The field would not say, which every formatter treats as the start of a sentence.
        case unknown
    }

    /// The most characters kept before the caret.
    public static let precedingLimit = 300
    /// The most characters kept after the selection.
    public static let followingLimit = 100

    /// Text before the caret, or `nil` when the field will not report its value.
    public let precedingText: String?
    /// Text after the selection, or `nil` when the field will not report its value.
    public let followingText: String?

    public init(precedingText: String? = nil, followingText: String? = nil) {
        self.precedingText = precedingText
        self.followingText = followingText
    }

    /// The insertion point of a field that says nothing about itself.
    public static let unknown = InsertionPoint()

    /// Derived from the preceding text, never read from the field.
    public var sentenceState: SentenceState { Self.sentenceState(before: precedingText) }

    /// Whether the caret's line opens with a list marker, so added text stays an unfinished list item.
    public var isOnListItemLine: Bool {
        guard let precedingText else { return false }
        let line =
            precedingText.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).last ?? ""
        return Self.listItemRemainder(in: line) != nil
    }

    /// Reads the sentence state off the line the caret sits on, since a list marker is not a word.
    public static func sentenceState(before text: String?) -> SentenceState {
        guard let text else { return .unknown }
        // Any line break ends the line, and a CRLF pair is one `Character`, so it is one break.
        let line = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).last ?? ""
        let body = withoutOpeningMarker(line)
        guard body.contains(where: { !$0.isWhitespace }) else {
            // Only a marker, a blank line or an empty field stands here; a line break still opened a line.
            let isBlank = line.allSatisfy(\.isWhitespace)
            return isBlank && text.contains(where: \.isNewline) ? .startOfSentence : .startOfText
        }
        let terminal = body.reversed().drop(while: Self.isTrailingSentenceDecoration).first
        if let terminal, sentenceEnds.contains(terminal) {
            let word =
                body.dropLast(while: Self.isTrailingSentenceDecoration)
                .split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
            let normalizedWord = String(
                word.lowercased().reversed()
                    .drop(while: { ".!?…,:;\"'”’)]}".contains($0) })
                    .reversed()
                    .drop(while: { "\"'“(".contains($0) })
            )
            let isKnownAbbreviation =
                sentenceAbbreviations.contains(normalizedWord)
                || normalizedWord.split(separator: ".").count > 1
            if !word.isEmpty, !isKnownAbbreviation {
                return .startOfSentence
            }
        }
        return .midSentence
    }

    /// The line without the one list, quote or heading marker it opens with, which is typed but not written.
    private static func withoutOpeningMarker(_ line: Substring) -> Substring {
        if let list = listItemRemainder(in: line) { return list }
        let body = line.drop(while: \.isWhitespace)
        if let marker = openingMarkers.first(where: { body.hasPrefix($0) }) {
            // A run of the same mark is one marker: "## " is a heading, ">>" a quotation inside a quotation.
            return body.drop { String($0) == marker }
        }
        return body
    }

    /// The text after the bullet or number that opens a list item.
    private static func listItemRemainder(in line: Substring) -> Substring? {
        let body = line.drop(while: \.isWhitespace)
        if let marker = Draft.bulletTokens.sorted().first(where: { body.hasPrefix($0) }) {
            return body.drop { String($0) == marker }
        }
        let digits = body.prefix(while: \.isNumber)
        let closingMark = body.dropFirst(digits.count)
        guard !digits.isEmpty, closingMark.first.map({ ".)".contains($0) }) == true else { return nil }
        return closingMark.dropFirst()
    }

    /// What a line may open with that is a marker rather than words: a list item, a quotation, a heading.
    private static let openingMarkers: [String] =
        Draft.bulletTokens.sorted() + ["#", ">", "\"", "'", "\u{201C}", "\u{2018}", "(", "[", "{"]

    /// The marks after which a new sentence begins, including the system's single-character ellipsis substitution.
    private static let sentenceEnds: Set<Character> = [".", "!", "?", "…"]

    /// Whether one trailing character does not change the sentence end before it.
    private static func isTrailingSentenceDecoration(_ character: Character) -> Bool {
        character.isWhitespace || closingSentenceCharacters.contains(character)
            || character.unicodeScalars.contains {
                $0.properties.isEmojiPresentation || $0.properties.isEmoji && $0.value >= 0x1F000
            }
    }

    /// Closing quotes and brackets may follow a sentence end without changing it.
    private static let closingSentenceCharacters: Set<Character> = ["\"", "'", "”", "’", ")", "]", "}"]

    /// Dotted forms that keep the current sentence open, shared with first-word casing.
    public static let sentenceAbbreviations: Set<String> = ["e.g", "i.e", "vs", "etc", "p.m", "a.m"]

    /// Pads `text` with a space at each caret edge where it would otherwise join a neighbouring word.
    public func paddedBoundary(for text: String) -> String {
        // A field that hides its preceding text gets the dictated text unchanged.
        guard let preceding = precedingText, !text.isEmpty, !text.allSatisfy(\.isWhitespace) else {
            return text
        }
        var result = ""
        if Self.requiresLeadingSpace(in: text, precedingText: preceding) {
            result += " "
        }
        result += text
        if let following = followingText, Self.requiresTrailingSpace(in: text, followingText: following) {
            result += " "
        }
        return result
    }

    /// Whether the dictated word needs a leading space to read as joined onto `precedingText`.
    private static func requiresLeadingSpace(in text: String, precedingText: String) -> Bool {
        // The dictated text already opens with its own whitespace, so the field is already joined.
        if text.first?.isWhitespace == true { return false }
        // Punctuation and clitics attach to preceding text instead of opening a new word.
        if text.first.map(attachingPunctuation.contains) == true
            || attachingCliticPrefixes.contains(where: text.hasPrefix)
        {
            return false
        }
        guard let previous = precedingText.last, !previous.isWhitespace, !previous.isNewline else {
            return false
        }
        return !openingBracket.contains(previous) && !Self.isOpeningStraightQuote(previous, in: precedingText)
    }

    /// Whether a straight quote follows a boundary that opens a quoted span.
    private static func isOpeningStraightQuote(_ quote: Character, in precedingText: String) -> Bool {
        guard quote == "\"" || quote == "'" else { return false }
        guard let beforeQuote = precedingText.dropLast().last else { return true }
        return beforeQuote.isWhitespace || openingBracket.contains(beforeQuote)
    }

    /// Whether the dictated word needs a trailing space to read as separate from `followingText`.
    private static func requiresTrailingSpace(in text: String, followingText: String) -> Bool {
        // The dictated text already closes with its own whitespace, so the field is already split.
        if text.last?.isWhitespace == true { return false }
        guard let next = followingText.first else { return false }
        return next.isLetter || next.isNumber || next == "_"
    }

    /// Brackets and curly opening quotes that start a context the dictated word belongs inside.
    private static let openingBracket: Set<Character> = ["(", "[", "{", "\u{201C}", "\u{2018}"]

    /// Punctuation and clitics that attach to the text before the caret.
    private static let attachingPunctuation: Set<Character> = [
        ",", ".", ";", ":", "!", "?", ")", "]", "}", "\"", "'", "”", "’",
    ]

    /// Clitic spellings whose first character is not punctuation.
    private static let attachingCliticPrefixes = ["n't", "n’t"]
}
