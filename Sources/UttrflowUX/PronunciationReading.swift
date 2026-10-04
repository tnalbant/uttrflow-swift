// What the "Say it like" text will do once the phonetic index keys it.

internal import Foundation
internal import UttrflowCore
internal import UttrflowDictionary

/// How the index will treat a pronunciation, so the editor can say so before it is saved.
enum PronunciationReading: Equatable {
    /// The pronunciation is the spelling closed up, so it keys nothing the spelling did not.
    case addsNothing
    /// One ordinary word, so every doubtful hearing of it becomes a candidate for the entry.
    case ordinaryWord(String)
    /// One function word, whose homophone changes the meaning; refused, as `GeneralVocabulary.wordsSounding` refuses it.
    case functionWord(String)
    /// Digits or symbols, which have no sound to key and are matched as written.
    case literal

    /// The reading of a pronunciation for a spelling; nil when it is blank or keys as an ordinary sounded phrase.
    static func of(pronunciation: String, for word: String) -> PronunciationReading? {
        let said = pronunciation.trimmingCharacters(in: .whitespacesAndNewlines)
        let written = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !said.isEmpty else { return nil }
        let words = said.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.count == 1, FunctionWords.holds(said) { return .functionWord(said) }
        if said.contains(where: isLiteral) { return .literal }
        if !written.isEmpty, ReadingRestraint.closedUp(said) == ReadingRestraint.closedUp(written) {
            return .addsNothing
        }
        if words.count == 1, GeneralVocabulary.isOrdinary(said) { return .ordinaryWord(said) }
        return nil
    }

    /// A digit or a mark other than the joiners a sounded-out word is written with.
    private static func isLiteral(_ character: Character) -> Bool {
        character.isNumber
            || !(character.isLetter || character.isWhitespace || "-'\u{2019}".contains(character))
    }

    /// Whether the editor refuses to save it rather than only noting it.
    var refusesSaving: Bool {
        if case .functionWord = self { return true }
        return false
    }

    /// What the editor says under the field; for a function word, the reason it cannot be saved.
    func note(for word: String) -> String {
        let written = word.trimmingCharacters(in: .whitespacesAndNewlines)
        switch self {
        case .addsNothing:
            return "This is the spelling again, so it adds nothing. Leave it blank."
        case .ordinaryWord(let said):
            return """
                Uttrflow will offer \u{201C}\(written)\u{201D} whenever it doubts \u{201C}\(said)\u{201D}; \
                the screen or your own earlier words must back it.
                """
        case .functionWord(let said):
            return """
                \u{201C}\(said)\u{201D} is too common a small word to stand for \u{201C}\(written)\u{201D}; \
                swapping it would change what was said.
                """
        case .literal:
            return "Digits and symbols have no sound to match, so this is matched as written."
        }
    }
}
