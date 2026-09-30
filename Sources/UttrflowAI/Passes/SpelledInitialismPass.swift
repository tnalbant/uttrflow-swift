public import UttrflowCore

/// Joins consecutive spoken letter names into an initialism, keeping article "a" and pronoun "I" distinct.
public struct SpelledInitialismPass: WholeTextCleaningPass {
    public static let id: PassID = .spelledInitialism

    static let letterNamesForCasing: Set<String> = [
        "a", "be", "bee", "cee", "see", "dee", "e", "ef", "eff", "gee", "aitch", "i", "eye",
        "jay", "kay", "el", "ell", "em", "en", "oh", "pee", "cue", "queue", "ar", "are",
        "ess", "tee", "you", "vee", "doubleu", "ex", "why", "zee", "zed",
    ]

    private static let letterNames: [String: String] = [
        "a": "A", "be": "B", "bee": "B", "cee": "C", "see": "C", "dee": "D", "e": "E",
        "ef": "F", "eff": "F", "gee": "G", "aitch": "H", "i": "I", "eye": "I", "jay": "J",
        "kay": "K", "el": "L", "ell": "L", "em": "M", "en": "N", "oh": "O", "pee": "P",
        "cue": "Q", "queue": "Q", "ar": "R", "are": "R", "ess": "S", "tee": "T",
        "you": "U", "vee": "V", "doubleu": "W", "ex": "X", "why": "Y", "zee": "Z", "zed": "Z",
    ]

    private static let dottedPairs: Set<String> = ["eg", "ie"]
    private static let articleAcronyms: Set<String> = ["api", "asap"]

    public init() {}

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        var live = draft.presentIndices
        var position = 0
        while position < live.count {
            guard let end = runEnd(from: position, in: live, draft: draft), end - position >= 2 else {
                position += 1
                continue
            }
            let letters = live[position..<end].compactMap { Self.letterNames[draft.shape(at: $0).key] }
            guard letters.count == end - position else {
                position += 1
                continue
            }
            let value = letters.joined()
            let output =
                Self.dottedPairs.contains(value.lowercased())
                ? letters.map { $0.lowercased() }.joined(separator: ".") + "."
                : value
            let first = live[position]
            draft.replace(
                at: first, with: Self.casedOutput(output, first: draft.words[first].text), by: Self.id)
            for index in live[(position + 1)..<end] { draft.remove(at: index, by: Self.id) }
            live.removeSubrange((position + 1)..<end)
            position += 1
        }
        return draft
    }

    private func runEnd(from position: Int, in live: [Int], draft: Draft) -> Int? {
        guard position < live.count, Self.letterNames[draft.shape(at: live[position]).key] != nil else {
            return nil
        }
        let token = draft.shape(at: live[position])
        let inSpokenPhrase = position > 0 && !draft.shape(at: live[position - 1]).endsClause
        if token.key == "a", inSpokenPhrase, token.core.first?.isUppercase != true {
            let candidateEnd = candidateRunEnd(from: position, in: live, draft: draft)
            let value = live[position..<candidateEnd].compactMap { Self.letterNames[draft.shape(at: $0).key] }
                .joined().lowercased()
            guard Self.articleAcronyms.contains(value) || Self.dottedPairs.contains(value) else { return nil }
        }
        let initialismStart = position
        var end = position + 1
        while end < live.count, !draft.shape(at: live[end - 1]).endsClause,
            !draft.words[live[end - 1]].isLayoutMark,
            !draft.words[live[end]].isLayoutMark,
            Self.letterNames[draft.shape(at: live[end]).key] != nil,
            (draft.shape(at: live[end]).key != "a" || end == initialismStart
                || end + 1 < live.count
                    && Self.letterNames[draft.shape(at: live[end + 1]).key] != nil
                    && draft.shape(at: live[end + 1]).key != "a")
        {
            end += 1
        }
        return end
    }

    private func candidateRunEnd(from position: Int, in live: [Int], draft: Draft) -> Int {
        var end = position
        while end < live.count, !draft.shape(at: live[end]).endsClause,
            !draft.words[live[end]].isLayoutMark,
            Self.letterNames[draft.shape(at: live[end]).key] != nil
        {
            end += 1
        }
        return end
    }

    private static func casedOutput(_ output: String, first: String) -> String {
        let shape = WordShape(first)
        guard shape.core.first?.isUppercase == true, !output.contains(".") else { return output }
        return WordShape.capitalised(output)
    }
}
