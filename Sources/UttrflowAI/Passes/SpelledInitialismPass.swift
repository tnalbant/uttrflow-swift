public import UttrflowCore

/// Joins consecutive spoken letter names into an initialism, keeping article "a" and pronoun "I" distinct.
public struct SpelledInitialismPass: WholeTextCleaningPass {
    public static let id: PassID = .spelledInitialism

    static let letterNames: [String: String] = [
        "a": "A", "b": "B", "be": "B", "bee": "B", "c": "C", "cee": "C", "see": "C",
        "d": "D", "dee": "D", "e": "E", "f": "F", "ef": "F", "eff": "F", "g": "G",
        "gee": "G", "h": "H", "aitch": "H", "i": "I", "eye": "I", "j": "J", "jay": "J",
        "k": "K", "kay": "K", "l": "L", "el": "L", "ell": "L", "m": "M", "em": "M",
        "n": "N", "en": "N", "o": "O", "oh": "O", "p": "P", "pee": "P", "q": "Q",
        "cue": "Q", "queue": "Q", "r": "R", "ar": "R", "are": "R", "s": "S", "ess": "S",
        "t": "T", "tee": "T", "u": "U", "you": "U", "v": "V", "vee": "V", "w": "W",
        "doubleu": "W", "x": "X", "ex": "X", "y": "Y", "why": "Y", "z": "Z", "zee": "Z",
        "zed": "Z",
    ]
    static let letterNamesForCasing = Set(letterNames.keys)

    private static let dottedPairs: Set<String> = ["eg", "ie"]

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
            guard candidateEnd - position >= 3 || Self.dottedPairs.contains(value) else { return nil }
        }
        let initialismStart = position
        var end = position + 1
        while end < live.count, !draft.shape(at: live[end - 1]).endsClause,
            live[end] == live[end - 1] + 1,
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
            end == position || live[end] == live[end - 1] + 1,
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
