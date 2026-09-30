import NaturalLanguage
public import UttrflowCore

/// Turns "new line", "new paragraph", "bullet point" and "number one" into layout, between words only.
public struct LayoutWordsPass: CleaningPass {
    public static let id: PassID = .layoutWords

    private let layout: LayoutPolicy
    private let insertionState: InsertionPoint.SentenceState

    /// What each spoken phrase becomes; a bullet marker carries its own dash and space.
    static let marks: [(words: [String], mark: String, requiresLists: Bool)] = [
        (["new", "line"], "\n", false), (["new", "paragraph"], "\n\n", false),
        (["blank", "line"], "\n\n", false), (["bullet", "point"], "\n- ", true),
        (["next", "point"], "\n- ", true),
    ]

    /// The word that opens a numbered item. It is not in `marks` because the number after it picks the mark.
    static let numbering = "number"

    public init(
        layout: LayoutPolicy = [.paragraphs, .lists], insertionPoint: InsertionPoint = .unknown
    ) {
        self.layout = layout
        self.insertionState = insertionPoint.sentenceState
    }

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        var live = draft.presentIndices
        let numbered = Set(live.indices.compactMap { itemValue(at: $0, in: live, of: draft) })
        var position = 0
        while position < live.count {
            guard
                let found = opening(mark(at: position, in: live, of: draft), at: position),
                position + found.length < live.count,
                isUsed(found, at: position, in: live, of: draft),
                isCorroborated(at: position, in: live, of: draft, among: numbered)
            else {
                position += 1
                continue
            }
            draft.replace(at: live[position], with: found.mark, by: Self.id)
            for index in live[position + 1..<position + found.length] {
                draft.remove(at: index, by: Self.id)
            }
            live.removeSubrange(position + 1..<position + found.length)
            position += 1
        }
        return draft
    }

    /// At the head, a break depends on the insertion point; an item number keeps its existing behavior.
    private func opening(
        _ found: (length: Int, mark: String)?, at position: Int
    ) -> (length: Int, mark: String)? {
        guard let found, position == 0 else { return found }
        guard found.mark.allSatisfy(\.isNewline) else { return found }
        switch insertionState {
        case .startOfText:
            return (found.length, "")
        case .startOfSentence, .midSentence:
            return found
        case .unknown:
            return nil
        }
    }

    /// Whether the phrase is dictated layout rather than named; an item opening its sentence needs a mark. See `Docs/cleanup.md`.
    private func isUsed(
        _ found: (length: Int, mark: String), at position: Int, in live: [Int], of draft: Draft
    ) -> Bool {
        let length = found.length
        if position == 0, found.mark.allSatisfy(\.isNewline), insertionState != .unknown { return true }
        // Asked of the sentence, not the text, so a sentence before it cannot turn "number one is broken" into an item.
        guard position == 0 || draft.shape(at: live[position - 1]).endsSentence else {
            return !MentionGuard.isMentioned(
                at: position, spanning: length, in: live, of: draft, reach: MentionGuard.phraseReach,
            )
        }
        // A break straight after a sentence's stop is how people dictate one: "full stop new paragraph".
        if position > 0, found.mark.allSatisfy(\.isNewline) { return true }
        let last = draft.shape(at: live[position + length - 1])
        return last.endsClause && !last.endsSentence
    }

    /// Whether a numbered item inside its sentence has a neighbouring item said beside it, since a lone one is a designator.
    private func isCorroborated(
        at position: Int, in live: [Int], of draft: Draft, among numbered: Set<Int>
    ) -> Bool {
        guard position > 0, !draft.shape(at: live[position - 1]).endsSentence,
            let value = itemValue(at: position, in: live, of: draft)
        else { return true }
        guard
            (value > 1 && numbered.contains(value - 1))
                || (value < Int.max && numbered.contains(value + 1))
        else { return false }
        return isEligibleNumberedRun(at: value, in: live, of: draft, among: numbered)
    }

    /// A lead-in and items without a stranded coordinator distinguish a list from a sentence.
    private func isEligibleNumberedRun(
        at value: Int, in live: [Int], of draft: Draft, among numbered: Set<Int>
    ) -> Bool {
        let positionsByValue = Dictionary(
            numbered.compactMap { position -> (Int, Int)? in
                guard let item = itemValue(at: position, in: live, of: draft) else { return nil }
                return (item, position)
            }, uniquingKeysWith: { first, _ in first },
        )
        var first = value
        while first > 1, positionsByValue[first - 1] != nil { first -= 1 }
        var item = first
        var firstMarker: Int?
        var hasJoiningWord = false
        while let marker = positionsByValue[item] {
            if firstMarker == nil { firstMarker = marker }
            if marker > 0 {
                let previous = draft.shape(at: live[marker - 1]).key
                hasJoiningWord = hasJoiningWord || previous == "and" || previous == "or"
            }
            guard item < Int.max else { return false }
            item += 1
        }
        guard let firstMarker else { return false }
        return !hasJoiningWord && isLeadInBefore(firstMarker, in: live, of: draft)
    }

    /// A mid-sentence list starts after a lead-in, not after a running clause.
    private func isLeadInBefore(_ marker: Int, in live: [Int], of draft: Draft) -> Bool {
        guard marker > 0, !draft.shape(at: live[marker - 1]).endsSentence else { return true }
        let previous = draft.shape(at: live[marker - 1])
        guard !["and", "or"].contains(previous.key) else { return false }
        if ["need", "are", "check"].contains(previous.key) { return true }
        let context = live[..<marker].map { draft.words[$0].text }.joined(separator: " ")
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = context
        guard let range = context.range(of: previous.core, options: .backwards) else { return false }
        return tagger.tag(at: range.lowerBound, unit: .word, scheme: .lexicalClass).0 != .verb
    }

    /// The number of the item "number" opens at `position`, or nil where no item opens.
    private func itemValue(at position: Int, in live: [Int], of draft: Draft) -> Int? {
        guard draft.shape(at: live[position]).key == Self.numbering, position + 1 < live.count else {
            return nil
        }
        return itemNumber(at: position + 1, in: live, of: draft)?.value
    }

    /// The layout the words at `position` become: one of the fixed phrases, or a numbered item.
    private func mark(at position: Int, in live: [Int], of draft: Draft) -> (length: Int, mark: String)? {
        if let found = Self.marks.first(where: {
            matches($0.words, at: position, in: live, of: draft)
                && (layout.contains(.lists) || !$0.requiresLists)
        }) {
            return (found.words.count, found.mark)
        }
        guard draft.shape(at: live[position]).key == Self.numbering, position + 1 < live.count,
            layout.contains(.lists),
            let item = itemNumber(at: position + 1, in: live, of: draft)
        else { return nil }
        return (item.count + 1, "\n\(item.value). ")
    }

    /// The item number, spoken or already a numeral, and how many words it took. See `Docs/cleanup.md`.
    private func itemNumber(at position: Int, in live: [Int], of draft: Draft) -> (value: Int, count: Int)? {
        let key = draft.shape(at: live[position]).key
        if let digits = NumberWords.digits(key) {
            guard let value = Int(digits), value > 0 else { return nil }
            return (value, 1)
        }
        let keys = live[draft.sentenceRun(from: position, in: live)].map { draft.shape(at: $0).key }
        guard let spoken = NumberWords.cardinal(keys[...]), spoken.value > 0 else { return nil }
        return spoken
    }

    private func matches(_ words: [String], at position: Int, in live: [Int], of draft: Draft) -> Bool {
        position + words.count <= live.count
            && draft.sentenceRun(from: position, in: live).count >= words.count
            && zip(words, live[position..<position + words.count]).allSatisfy {
                $0 == draft.shape(at: $1).key
            }
    }
}
