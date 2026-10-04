import UttrflowCore
import UttrflowDictionary

// The guard's checks on layout, list marks, breaks, quotation marks and the text's overall shape.
extension MeaningPreservationGuard {
    /// Refuses a rewrite that flattened a break the speaker asked for, since layout is the passes' to decide.
    static func layoutVerdict(
        kept: String, rewritten: String, layout: LayoutPolicy = [.paragraphs, .lists]
    ) -> GuardVerdict {
        let wanted = breaks(in: kept)
        let got = breaks(in: rewritten)
        guard wanted.paragraphs <= got.paragraphs, wanted.lines <= got.lines else {
            return .rejected(reason: "the rewrite dropped a line break the speaker asked for", kind: .layout)
        }
        // A list may be laid out and never composed, so one may appear only where the destination lays them out.
        guard layout.contains(.lists) || listMarks(in: rewritten) <= listMarks(in: kept) else {
            return .rejected(reason: "the rewrite composed a list the speaker did not speak", kind: .layout)
        }
        // Somewhere with no paragraphs to make, a break the speaker did not ask for is the model's own shape.
        guard layout.contains(.paragraphs) || got.paragraphs + got.lines <= wanted.paragraphs + wanted.lines
        else {
            return .rejected(
                reason: "the rewrite added a line break the speaker did not ask for", kind: .layout)
        }
        return .accepted
    }

    /// List items, counted the way every pass counts them, so the guard and the passes agree on what one is.
    private static func listMarks(in text: String) -> Int {
        Draft(keepingLineBreaks: text).words.count { $0.isListMark }
    }

    /// Paragraph breaks and line breaks, counting a paragraph as one break rather than two lines.
    private static func breaks(in text: String) -> (paragraphs: Int, lines: Int) {
        let paragraphs = text.components(separatedBy: "\n\n").count - 1
        let lines = text.filter { $0.isNewline }.count - paragraphs
        return (paragraphs, lines)
    }

    /// Accepts a rewrite unless it is empty, chatty (unless excused), far longer, mostly dropped, invents a number, or adds quotation or exclamation marks.
    static func textVerdict(original: String, rewritten: String, excusingPreamble: Bool) -> GuardVerdict {
        let originalWords = TextTidy.words(original)
        let rewrittenWords = TextTidy.words(rewritten)

        if !originalWords.isEmpty, rewrittenWords.isEmpty {
            return .rejected(reason: "the rewrite is empty", kind: .emptyRewrite)
        }
        if case .rejected(let reason, let kind) = Self.spokenAmpersandVerdict(
            original: original, rewritten: rewritten)
        {
            return .rejected(reason: reason, kind: kind)
        }
        // A speaker who opens with "I have" or "sure" gets their words; the entry's punctuation is the model's, not theirs.
        if !excusingPreamble,
            let preamble = Self.preambles.first(where: {
                rewritten.lowercased().hasPrefix($0)
                    && !original.lowercased().hasPrefix($0.trimmingCharacters(in: .punctuationCharacters))
            })
        {
            return .rejected(reason: "the rewrite begins with '\(preamble)'", kind: .preamble)
        }
        if Double(rewrittenWords.count) > Double(originalWords.count) * Self.maximumGrowthFactor + 4 {
            return .rejected(reason: "the rewrite is far longer than what was said", kind: .tooLong)
        }
        if originalWords.count > Self.shortUtteranceWords {
            let retained = Double(rewrittenWords.count) / Double(originalWords.count)
            if retained < Self.minimumRetainedFraction {
                return .rejected(reason: "the rewrite dropped most of what was said", kind: .tooShort)
            }
        }
        if let invented = Self.inventedNumber(original: original, rewritten: rewritten) {
            return .rejected(reason: "the rewrite introduced the number \(invented)", kind: .inventedNumber)
        }
        if let changed = Self.changedQuantity(original: original, rewritten: rewritten) {
            return .rejected(reason: "the rewrite wrote \(changed) as another amount", kind: .changedNumber)
        }
        if let changed = Self.changedIndianGrouping(original: original, rewritten: rewritten) {
            return .rejected(
                reason: "the rewrite changed the Indian grouping in \(changed)", kind: .changedNumber)
        }
        if Self.addsQuotationPair(original: original, rewritten: rewritten) {
            return .rejected(reason: "the rewrite added quotation marks", kind: .inventedQuotation)
        }
        if rewritten.count(where: { $0 == "!" }) > original.count(where: { $0 == "!" }) {
            return .rejected(reason: "the rewrite added an exclamation mark", kind: .inventedExclamation)
        }
        return .accepted
    }

    /// Refuses a rewrite that spells a spoken ampersand as "and" or turns "and" into an ampersand.
    static func spokenAmpersandVerdict(original: String, rewritten: String) -> GuardVerdict {
        let heard = original.filter { $0 == "&" }.count
        let written = rewritten.filter { $0 == "&" }.count
        guard heard == written else {
            return .rejected(reason: "the rewrite changed a spoken ampersand", kind: .lostWord)
        }
        return .accepted
    }

    /// Whether the rewrite adds a quoted word span that has no counterpart in the draft.
    private static func addsQuotationPair(original: String, rewritten: String) -> Bool {
        var originalSpans = quotationSpans(in: original)
        for span in quotationSpans(in: rewritten) {
            guard let match = originalSpans.firstIndex(of: span) else { return true }
            originalSpans.remove(at: match)
        }
        return false
    }

    /// The word spans held by straight and curly quotation pairs.
    private static func quotationSpans(in text: String) -> [String] {
        let characters = Array(text)
        let pairs: [(Character, Character)] = [
            ("\"", "\""), ("\u{201C}", "\u{201D}"), ("\u{2018}", "\u{2019}"),
            ("'", "'"),
        ]
        return pairs.flatMap { open, close in
            let openings = characters.indices.filter { characters[$0] == open }
                .filter { !isApostropheDelimiter(at: $0, in: characters) }
            let closings = characters.indices.filter { characters[$0] == close }
                .filter { !isApostropheDelimiter(at: $0, in: characters) }
            var unmatched = openings
            var spans: [String] = []
            for closing in closings {
                guard let index = unmatched.firstIndex(where: { $0 < closing }) else { continue }
                let opening = unmatched.remove(at: index)
                let content = String(characters[(opening + 1)..<closing])
                spans.append(grammarTokens(content).map(\.matching).joined(separator: " "))
            }
            return spans
        }
    }

    /// Whether a single quote mark is an apostrophe or a decade elision rather than a delimiter.
    private static func isApostropheDelimiter(at index: Int, in characters: [Character]) -> Bool {
        (characters[index] == "'" || characters[index] == "\u{2019}")
            && (isWordApostrophe(at: index, in: characters) || isDecadeElision(at: index, in: characters))
    }

    /// Whether an apostrophe stands between two letters in one word.
    private static func isWordApostrophe(at index: Int, in characters: [Character]) -> Bool {
        index > 0 && index + 1 < characters.count
            && characters[index - 1].isLetter && characters[index + 1].isLetter
    }

    /// Whether an apostrophe abbreviates the leading digits of a decade such as ’90s.
    private static func isDecadeElision(at index: Int, in characters: [Character]) -> Bool {
        guard index + 2 < characters.count, characters[index + 1].isNumber,
            characters[index + 2].isNumber
        else { return false }
        return index + 3 == characters.count || !characters[index + 3].isNumber
    }
}
