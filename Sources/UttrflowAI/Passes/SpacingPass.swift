public import UttrflowCore

/// Fixes a mark that arrived as its own word onto the word before it, and settles each run of marks to its legal form.
public struct SpacingPass: PieceCleaningPass {
    public static let id: PassID = .spacing

    static let clauseMarks: Set<Character> = [",", ".", "?", "!", ":", ";"]

    public init() {}

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        var previous: Int?
        for index in draft.presentIndices {
            let text = draft.words[index].text
            if let previous, text.allSatisfy(Self.clauseMarks.contains) {
                let merged = WordShape.settlingMarks(draft.words[previous].text + text)
                draft.replace(at: previous, with: merged, by: Self.id)
                draft.remove(at: index, by: Self.id)
                continue
            }
            draft.replace(at: index, with: WordShape.settlingMarks(text), by: Self.id)
            previous = index
        }
        return draft
    }
}
