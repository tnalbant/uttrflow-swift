public import UttrflowCore

/// Takes back a full stop when the same boundary evidence used at piece seams shows a sentence continuing.
public struct SentenceBoundaryPass: WholeTextCleaningPass {
    public static let id: PassID = "sentenceBoundary"

    public init() {}

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        let live = draft.presentIndices
        guard live.count > 1 else { return draft }
        for position in live.indices.dropLast() {
            let index = live[position]
            let nextIndex = live[position + 1]
            let shape = draft.shape(at: index)
            guard shape.suffix == ".", !draft.words[nextIndex].isLayoutMark else { continue }
            guard !InsertionPoint.sentenceAbbreviations.contains(shape.key) else { continue }
            let following = live[(position + 1)...].map { draft.words[$0].text }.joined(separator: " ")
            let heardShape = WordShape(draft.words[nextIndex].heard)
            guard
                SentenceBoundaryEvidence.sentenceRunsOn(
                    WordShape.withoutTrailingStop(draft.words[index].text), into: following,
                    nextWordWasLowercase: heardShape.core.first?.isLowercase == true
                )
            else { continue }

            let conjunction = draft.shape(at: nextIndex).key
            let mark = conjunction == "but" || conjunction == "so" ? "," : ""
            let repaired = WordShape.withoutTrailingStop(draft.words[index].text)
            draft.replace(
                at: index, with: mark.isEmpty ? repaired : WordShape.marked(repaired, with: mark), by: Self.id
            )

            let next = draft.shape(at: nextIndex)
            guard next.key != "i", !FirstWordPass.keepsCapital(next.core),
                !FirstWordPass.isProperName(next.core, in: draft.text),
                !FirstWordPass.isCalendarWord(next.core)
            else { continue }
            draft.replace(at: nextIndex, with: WordShape.lowercased(draft.words[nextIndex].text), by: Self.id)
        }
        return draft
    }
}
