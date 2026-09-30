public import UttrflowCore

/// Removes hesitation sounds while keeping standalone replies and fixed interjections.
public struct FillersPass: CleaningPass {
    public static let id: PassID = .fillers
    public static let removes: RemovalGrant = .sound

    /// Whole words that carry no meaning; "like", "well", "so", "basically" and "mm" (millimetres) are out.
    static let fillerWords: Set<String> = [
        "um", "umm", "uh", "uhh", "uhm", "er", "erm", "ah", "hmm", "mmm", "aah", "ahh", "mhm",
    ]

    /// Words a sentence sets off with a comma of its own, which a removed filler beside them leaves in place.
    static let discourseWords: Set<String> = [
        "yes", "no", "yeah", "okay", "ok", "well", "thanks", "so", "now", "actually",
    ]

    private static let standaloneReplies: Set<String> = ["hmm", "mhm"]
    public init() {}

    /// Whether the comma before a bracketed filler belongs to the sentence rather than to the pause.
    private func sentenceOwnsComma(
        before: Int, fillerAt position: Int, in live: [Int], of draft: Draft
    ) -> Bool {
        if Self.discourseWords.contains(draft.shape(at: before).key) { return true }
        if position + 1 < live.count, Self.discourseWords.contains(draft.shape(at: live[position + 1]).key) {
            return true
        }
        guard let at = live.firstIndex(of: before) else { return false }
        if at == 0 { return true }
        let last = draft.words[live[at - 1]].text.last
        return last == "." || last == "?" || last == "!"
    }

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        let live = draft.presentIndices
        var previous: Int?
        var consumed: Set<Int> = []
        for (position, index) in live.enumerated() {
            guard !consumed.contains(index) else { continue }
            let word = draft.words[index].text
            if let pair = Self.interjection(at: position, in: live, of: draft) {
                let shape = draft.shape(at: index)
                let written = position == 0 ? WordShape.capitalised(pair.written) : pair.written
                draft.replace(at: index, with: shape.replacingCore(with: written), by: Self.id)
                draft.remove(at: pair.second, by: Self.id, carryingMarks: true)
                consumed.insert(pair.second)
                previous = index
                continue
            }
            if live.count == 1, Self.standaloneReplies.contains(draft.shape(at: index).key) {
                previous = index
                continue
            }
            // A filler sound is never preceded by a determiner; a noun spelled like one — "the ER" — always is.
            guard Self.fillerWords.contains(draft.shape(at: index).key),
                position == 0
                    || !MentionGuard.isMentioned(at: position, spanning: 1, in: live, of: draft)
            else {
                previous = index
                continue
            }
            // A filler bracketed by commas takes the opening one too, unless the sentence needs it.
            if word.hasSuffix(","), let before = previous, draft.words[before].text.hasSuffix(","),
                !sentenceOwnsComma(before: before, fillerAt: position, in: live, of: draft)
            {
                draft.replace(
                    at: before, with: String(draft.words[before].text.dropLast()), by: Self.id)
            }
            if Self.stopIsThePause(at: position, in: live, of: draft) {
                Self.runOn(live[position + 1], in: &draft)
                draft.replace(at: index, with: draft.shape(at: index).core, by: Self.id)
            }
            draft.remove(at: index, by: Self.id, carryingMarks: true)
        }
        return draft
    }

    /// Joins the two heard words that form a fixed assent or alarm reply.
    private static func interjection(
        at position: Int, in live: [Int], of draft: Draft
    ) -> (second: Int, written: String)? {
        guard position + 1 < live.count else { return nil }
        let first = draft.shape(at: live[position])
        let secondIndex = live[position + 1]
        let second = draft.shape(at: secondIndex)
        guard first.prefix.isEmpty, first.suffix.isEmpty, second.prefix.isEmpty
        else { return nil }
        let written: String
        switch (first.key, second.key) {
        case ("uh", "huh"): written = "uh-huh"
        case ("uh", "oh"): written = "uh-oh"
        case ("mm", "hmm"): written = "mm-hmm"
        default: return nil
        }
        return (secondIndex, written)
    }

    /// Whether the filler's full stop marks the pause in a clause: the next word runs on in lower case, or the one before cannot end a sentence.
    static func stopIsThePause(at position: Int, in live: [Int], of draft: Draft) -> Bool {
        guard draft.shape(at: live[position]).suffix == ".", position > 0, position + 1 < live.count
        else { return false }
        let before = draft.words[live[position - 1]]
        let after = draft.words[live[position + 1]]
        let marks = WordShape(before.text).suffix
        guard !before.isLayoutMark, !after.isLayoutMark, marks.isEmpty || WordShape.trailsOff(marks)
        else { return false }
        return WordShape.lowercased(after.text) == after.text
            || FunctionWords.leadsOn(WordShape(before.text).key)
    }

    /// Lowers the capital the filler's stop gave the next word, unless it is "I", an acronym or a name the text shows.
    private static func runOn(_ index: Int, in draft: inout Draft) {
        let word = draft.words[index].text
        guard !FirstWordPass.keepsCapital(word), !FirstWordPass.looksLikeName(word, in: [draft.text]) else {
            return
        }
        draft.replace(at: index, with: WordShape.lowercased(word), by: Self.id)
    }
}
