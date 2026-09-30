public import UttrflowCore

/// Adds or takes back the final full stop the way the formatter's stop policy and layout say.
public struct TerminalStopPass: WholeTextCleaningPass {
    public static let id: PassID = .terminalStop

    public let policy: TerminalStopPolicy
    public let layout: LayoutPolicy
    public let insertionPoint: InsertionPoint

    public init(
        policy: TerminalStopPolicy = .always, layout: LayoutPolicy = .paragraphs,
        insertionPoint: InsertionPoint = .unknown
    ) {
        self.policy = policy
        self.layout = layout
        self.insertionPoint = insertionPoint
    }

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        if layout.contains(.singleLine) { Self.flatten(&draft) }
        if layout.contains(.paragraphs), policy != .never { Self.stopParagraphs(&draft) }
        Self.separateTrailingRequest(&draft, layout: layout)
        guard let last = draft.presentIndices.last, !draft.words[last].isLayoutMark else { return draft }
        let word = draft.words[last].text
        let finished: String
        switch policy {
        case .always:
            finished = finishedLast(word, in: draft)
        case .never:
            finished = WordShape.withoutTrailingStop(word)
        case .offForShortMessages(let sentences):
            let stopped = finishedLast(word, in: draft)
            finished =
                Self.sentenceCount(draft.text) <= sentences ? WordShape.withoutTrailingStop(stopped) : stopped
        }
        draft.replace(at: last, with: finished, by: Self.id)
        return draft
    }

    /// Separates an unmarked trailing request from the statement before it.
    private static func separateTrailingRequest(_ draft: inout Draft, layout: LayoutPolicy) {
        guard layout.contains(.paragraphs) else { return }
        let live = draft.presentIndices
        let shapes = live.map { draft.shape(at: $0) }
        guard let start = QuestionShape.trailingRequestStart(in: shapes), start > 0,
            !draft.words[live[start - 1]].isLayoutMark,
            !shapes[start - 1].suffix.contains(where: { ".!?;,:".contains($0) })
        else { return }
        let index = live[start - 1]
        draft.replace(at: index, with: WordShape.marked(draft.words[index].text, with: ","), by: id)
    }

    /// The last word with a stop unless it ends a list item, or the layout keeps newlines and the text holds one.
    private func finishedLast(_ word: String, in draft: Draft) -> String {
        if followingTextContinuesSentence { return word }
        if insertionPoint.isOnListItemLine || draft.endsInListItem { return word }
        if layout.contains(.preserveNewlines), draft.text.contains(where: \.isNewline) { return word }
        // Only prose asks: "where total is greater than 12000" in a SQL editor is a clause, not a question.
        let asks = layout.contains(.paragraphs) && Self.lastSentenceAsks(draft)
        return asks
            ? WordShape.finished(WordShape.withoutTrailingStop(word), with: "?")
            : WordShape.finished(word)
    }

    /// Whether text after the replacement already ends or continues the sentence.
    private var followingTextContinuesSentence: Bool {
        guard let followingText = insertionPoint.followingText else { return false }
        let leadingWhitespace = followingText.prefix(while: \.isWhitespace)
        guard !leadingWhitespace.contains(where: \.isNewline),
            let next = followingText.dropFirst(leadingWhitespace.count).first
        else { return false }
        return ".!?…,:;".contains(next) || next.isLowercase
    }

    /// Whether the sentence the draft ends on asks a direct question by its word order.
    static func lastSentenceAsks(_ draft: Draft) -> Bool {
        let live = draft.presentIndices
        let start = live.dropLast().lastIndex {
            draft.words[$0].isLayoutMark || draft.shape(at: $0).endsSentence
        }
        let sentence = live[(start.map { $0 + 1 } ?? 0)...]
        return QuestionShape.asks(sentence.map { draft.shape(at: $0) })
    }

    /// Every layout mark taken out, so the words join on one line.
    private static func flatten(_ draft: inout Draft) {
        for index in draft.presentIndices where draft.words[index].isLayoutMark {
            draft.remove(at: index, by: id)
        }
    }

    /// Ends each paragraph of three or more words before a blank line with a full stop; a list item gets none.
    private static func stopParagraphs(_ draft: inout Draft) {
        var opening: Draft.Word?
        var paragraph: [Int] = []
        for index in draft.presentIndices {
            let word = draft.words[index]
            guard word.isLayoutMark else {
                paragraph.append(index)
                continue
            }
            if word.text.hasPrefix("\n\n"), let last = paragraph.last, paragraph.count >= 3,
                !(opening?.isListMark ?? false)
            {
                draft.replace(at: last, with: WordShape.finished(draft.words[last].text), by: id)
            }
            if word.text.hasPrefix("\n\n") || word.isListMark {
                opening = word
                paragraph = []
            }
        }
    }

    /// How many sentences the text holds; the joiner asks the same question of a whole dictation.
    static func sentenceCount(_ text: String) -> Int { SentenceCount.of(text) }
}
