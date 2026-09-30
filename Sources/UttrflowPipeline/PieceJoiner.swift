import UttrflowCore

/// One piece of the recording, through every stage that runs before the words are joined.
struct Piece: Sendable {
    let heard: Transcription
    let corrected: CorrectedTranscript
    let cleaned: TransformationResult
}

/// Joins the pieces of one dictation, laying out what only the seam between two of them can show. See `Docs/cleanup-design.md` §7.
enum PieceJoiner {
    static let id: PassID = "pieceJoiner"

    /// The finished transcript before seam stops are restored, with the affected seam positions retained.
    static func snippetInput(
        _ pieces: [Piece], under formatter: DestinationFormatter, using text: String
    ) -> SeamSnippetInput {
        guard pieces.count > 1 else { return SeamSnippetInput(text: text, removableStops: [], source: text) }
        let texts = pieces.map(\.cleaned.text)
        let seamed = seamed(texts, under: formatter)
        var removableStops: [Int] = []
        var original = ""
        for index in pieces.indices {
            if index > 0 { original += " " }
            original += seamed[index]
            if index < pieces.count - 1,
                String(seamed[index]) != String(texts[index]),
                let last = original.last, ".!?".contains(last)
            {
                removableStops.append(original.count - 1)
            }
        }
        let source = original
        let exact = source == text
        return SeamSnippetInput(
            text: text, removableStops: exact ? removableStops : [], source: exact ? source : text)
    }

    /// Every piece as one, with the corrections' word ranges moved to where their piece begins.
    static func join(_ pieces: [Piece], under formatter: DestinationFormatter) -> Piece {
        guard pieces.count > 1, let first = pieces.first else {
            return pieces.first
                ?? Piece(
                    heard: Transcription(text: ""), corrected: .unchanged(""),
                    cleaned: TransformationResult(text: "", producedBy: .rules))
        }
        var corrections: [DictationCorrection] = []
        var wordsBefore = 0
        var heardText: [String] = []
        var correctedText: [String] = []
        var producedBy = first.cleaned.producedBy
        for piece in pieces {
            corrections += piece.corrected.corrections.map { $0.shifted(by: wordsBefore) }
            wordsBefore += piece.heard.text.spokenWordCount
            heardText.append(piece.heard.text)
            correctedText.append(piece.corrected.text)
            // Any piece the model left to the rules makes the whole a rules result.
            if piece.cleaned.producedBy != producedBy { producedBy = .rules }
        }
        let heard = Transcription(
            text: heardText.joined(separator: " "),
            detectedLanguage: first.heard.detectedLanguage,
            segments: pieces.flatMap(\.heard.segments),
            audioDuration: pieces.reduce(.zero) { $0 + $1.heard.audioDuration })
        return Piece(
            heard: heard,
            corrected: CorrectedTranscript(
                text: correctedText.joined(separator: " "), corrections: corrections),
            cleaned: TransformationResult(
                text: laidOut(seamed(pieces.map(\.cleaned.text), under: formatter), under: formatter),
                producedBy: producedBy, entriesTaken: pieces.flatMap(\.cleaned.entriesTaken)))
    }

    /// Every piece but the last ended as a sentence the way the place ends one; the message's own stop is the cleaner's.
    static func seamed(_ pieces: [String], under formatter: DestinationFormatter) -> [String] {
        let pieces = joiningAmountsAcrossSeams(pieces)
        return pieces.enumerated().map { index, text in
            guard index > 0, sentenceRunsOn(pieces[index - 1], into: text) else {
                return index == pieces.count - 1
                    ? text : endedAtSeam(text, before: pieces[index + 1], under: formatter)
            }
            return lowercasedOpening(text, in: pieces[index - 1] + " " + text)
        }
    }

    /// Lowers a capital opened by the recognizer while keeping spellings the casing passes protect.
    private static func lowercasedOpening(_ text: String, in context: String) -> String {
        guard let start = text.firstIndex(where: { !$0.isWhitespace }),
            let end = text[start...].firstIndex(where: \.isWhitespace) ?? text.endIndex,
            let first = text[start..<end].first, first.isUppercase,
            !FirstWordPass.keepsCapital(String(text[start..<end])),
            !FirstWordPass.isCalendarWord(String(text[start..<end])),
            !FirstWordPass.looksLikeName(String(text[start..<end]), in: [context])
        else { return text }
        let word = String(text[start..<end])
        return text.replacingCharacters(in: start..<end, with: WordShape.lowercased(word))
    }

    /// Joins a bare numeral to a currency amount introduced by "and" across a piece boundary.
    private static func joiningAmountsAcrossSeams(_ pieces: [String]) -> [String] {
        guard pieces.count > 1 else { return pieces }
        var joined = pieces
        for index in 0..<(joined.count - 1) {
            let following = joined[index + 1].split(whereSeparator: \.isWhitespace)
            guard let last = joined[index].split(whereSeparator: \.isWhitespace).last,
                following.count == 2, WordShape(String(following[0])).key == "and",
                let leadingValue = integer(String(last)),
                let amount = currencyAmount(String(following[1]))
            else { continue }
            let (sum, overflow) = leadingValue.addingReportingOverflow(amount.value)
            guard !overflow else { continue }
            let replacement = amount.symbol + NumberWords.render(sum, grouped: true)
            let prefix = String(joined[index].dropLast(last.count))
            joined[index] = prefix + replacement
            joined[index + 1] = ""
        }
        return joined
    }

    /// Reads a grouped or ungrouped nonnegative integer.
    private static func integer(_ text: String) -> Int? {
        let digits = text.replacingOccurrences(of: ",", with: "")
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }
        return Int(digits)
    }

    /// Reads the currency symbol and integer value from a cleaned amount.
    private static func currencyAmount(_ text: String) -> (symbol: String, value: Int)? {
        guard let symbol = text.first, "$€£₹".contains(symbol),
            let value = integer(String(text.dropFirst()))
        else { return nil }
        return (String(symbol), value)
    }

    /// One piece ended at a seam, unless the words on either side of the cut say the sentence ran through it. See `Docs/cleanup-design.md` §7.
    private static func endedAtSeam(
        _ text: String, before next: String, under formatter: DestinationFormatter
    ) -> String {
        if formatter.terminalStop == .never { return WordShape.withoutTrailingStop(text) }
        if next.split(whereSeparator: \.isWhitespace).isEmpty { return text }
        let piece = Draft(keepingLineBreaks: text)
        guard let last = text.last, !last.isNewline, !piece.endsInListItem,
            !(formatter.layout.contains(.preserveNewlines) && text.contains(where: \.isNewline)),
            !sentenceRunsOn(text, into: next)
        else { return text }
        return WordShape.finished(text)
    }

    // MARK: The stop at a seam

    /// Whether the words across a seam show the sentence carried on, which is the one reason not to end it there.
    static func sentenceRunsOn(_ text: String, into next: String) -> Bool {
        SentenceBoundaryEvidence.sentenceRunsOn(text, into: next)
            || trailingTriggerDiscardsWords(in: text, before: next)
    }

    /// The cleaned pieces as one text: a spoken list, a paragraph at a topic, a restatement across the seam, else a space.
    static func laidOut(_ pieces: [String], under formatter: DestinationFormatter) -> String {
        var draft = Draft(words: [])
        var starts: [Int] = []
        for text in pieces {
            let piece = Draft(keepingLineBreaks: text)
            guard !piece.words.isEmpty else { continue }
            starts.append(draft.words.count)
            draft.words += piece.words
        }
        guard starts.count > 1 else { return draft.text }

        layoutCommands(&draft, at: starts, under: formatter)

        var marks: [Int: String] = [:]
        var absorbed: Set<Int> = []
        for opening in starts.indices.dropFirst() where restate(&draft, at: starts[opening]) {
            absorbed.insert(opening)
        }
        let items = formatter.layout.contains(.lists) ? listItems(in: draft, starts: starts) : []
        for (item, opening) in items.enumerated() {
            let isOrdinal = Self.ordinals[draft.shape(at: opening).key] != nil
            if let mark = itemise(&draft, opening, items: items, item: item, ordinal: isOrdinal) {
                marks[opening] = mark
            }
        }
        for opening in starts.indices.dropFirst() {
            guard paragraphs(formatter), !absorbed.contains(opening), !items.contains(opening),
                opensTopic(draft, at: starts[opening])
            else { continue }
            marks[starts[opening]] = "\n\n"
        }
        for (index, mark) in marks.sorted(by: { $0.key > $1.key }) {
            draft.insert(mark, at: index, by: id)
        }
        return draft.text
    }

    /// Turns an explicit layout phrase at a noninitial piece boundary into its mark.
    private static func layoutCommands(
        _ draft: inout Draft, at starts: [Int], under formatter: DestinationFormatter
    ) {
        let commands: [(words: [String], mark: String, requiresLists: Bool)] = [
            (["new", "line"], "\n", false), (["new", "paragraph"], "\n\n", false),
            (["blank", "line"], "\n\n", false), (["bullet", "point"], "\n- ", true),
            (["next", "point"], "\n- ", true),
        ]
        for opening in starts.indices.dropFirst() {
            let start = starts[opening]
            let end = opening + 1 < starts.count ? starts[opening + 1] : draft.words.count
            let live = draft.presentIndices
            guard let position = live.firstIndex(of: start) else { continue }
            guard
                let found = commands.first(where: { command in
                    (!command.requiresLists || formatter.layout.contains(.lists))
                        && (command.requiresLists
                            || formatter.layout.contains(.paragraphs)
                            || formatter.layout.contains(.preserveNewlines))
                        && position + command.words.count < live.count
                        && live[position + command.words.count - 1] < end
                        && zip(command.words, live[position..<position + command.words.count]).allSatisfy {
                            $0 == draft.shape(at: $1).key
                        }
                })
            else { continue }
            let body = live[position + found.words.count]
            if body < end {
                let shape = draft.shape(at: body)
                draft.replace(
                    at: body, with: shape.replacingCore(with: WordShape.capitalised(shape.core)), by: id)
            }
            draft.replace(at: start, with: found.mark, by: id)
            for index in live[(position + 1)..<(position + found.words.count)] {
                draft.remove(at: index, by: id)
            }
        }
    }

    /// Whether this place wants a blank line between topics at all.
    private static func paragraphs(_ formatter: DestinationFormatter) -> Bool {
        formatter.layout.contains(.paragraphs) && !formatter.layout.contains(.singleLine)
    }

    // MARK: Restatements across the seam

    /// Drops the tail the speaker replaced when a piece restates it, saying whether it did.
    private static func restate(_ draft: inout Draft, at word: Int) -> Bool {
        let live = draft.presentIndices
        guard let position = live.firstIndex(of: word), position > 0 else { return false }

        // The stop the piece before was given ends a sentence the speaker never did, so the match reaches through it.
        let last = live[position - 1]
        let stopped = draft.words[last].text
        draft.words[last].text = WordShape.withoutTrailingStop(stopped)
        guard let discarded = discarded(at: position, in: live, of: draft) else {
            draft.words[last].text = stopped
            return false
        }
        for index in live[discarded] { draft.remove(at: index, by: id) }
        return true
    }

    /// The half the piece opening at `position` takes back, trigger included, or nil when the halves do not match.
    private static func discarded(at position: Int, in live: [Int], of draft: Draft) -> Range<Int>? {
        let trigger = Restatement.triggerRun(at: position, in: live, of: draft)
        if trigger > 0, position + trigger < live.count,
            let start = Restatement.discardedStart(
                before: position, after: position + trigger, in: live, of: draft)
        {
            return start..<(position + trigger)
        }
        guard let tail = trailingTriggerStart(before: position, in: live, of: draft),
            position < live.count,
            let start = Restatement.discardedStart(
                before: tail, after: position, in: live, of: draft)
        else { return nil }
        return start..<position
    }

    /// Finds a correction trigger that ends exactly at the seam and takes back the words before it.
    private static func trailingTriggerStart(before position: Int, in live: [Int], of draft: Draft) -> Int? {
        for start in stride(from: position - 1, through: max(0, position - 3), by: -1) {
            let length = Restatement.triggerRun(at: start, in: live, of: draft)
            if length > 0, start + length == position { return start }
        }
        return nil
    }

    /// Whether a trigger at the end of this piece matches the opening words of the next one as a correction.
    private static func trailingTriggerDiscardsWords(in text: String, before next: String) -> Bool {
        let draft = Draft(text: text + " " + next)
        let live = draft.presentIndices
        let boundary = Draft(text: text).presentIndices.count
        guard boundary > 0, boundary < live.count,
            let trigger = trailingTriggerStart(before: boundary, in: live, of: draft),
            Restatement.discardedStart(before: trigger, after: boundary, in: live, of: draft) != nil
        else { return false }
        return true
    }

    // MARK: Lists from spoken sequence words

    /// The openings that are the items of one spoken list, or nothing when the pieces do not spell one.
    private static func listItems(in draft: Draft, starts: [Int]) -> [Int] {
        let live = draft.presentIndices
        guard !live.isEmpty else { return [] }

        // Ordinals are semantic boundaries even when working-ahead did not cut there.
        let startsSet = Set(starts)
        let ordinalCandidates = live.indices.compactMap {
            position -> (position: Int, value: Int)? in
            let shape = draft.shape(at: live[position])
            guard let value = Self.ordinals[shape.key],
                (position == live.startIndex || startsSet.contains(live[position])
                    || draft.shape(at: live[position - 1]).endsClause)
            else { return nil }
            return (position, value)
        }
        guard let ordinalHead = ordinalCandidates.firstIndex(where: { $0.value == 1 }),
            ordinalCandidates.count - ordinalHead >= 2,
            Array(ordinalCandidates[ordinalHead...]).enumerated().allSatisfy({ offset, candidate in
                candidate.value == offset + 1
            })
        else {
            return boundaryListItems(in: draft, starts: starts)
        }
        return Array(ordinalCandidates[ordinalHead...]).map { live[$0.position] }
    }

    /// Recognizes announced and cardinal sequences at piece boundaries, where their number is unambiguous.
    private static func boundaryListItems(in draft: Draft, starts: [Int]) -> [Int] {
        let live = draft.presentIndices
        let candidates = starts.enumerated().compactMap { index, start in
            guard let found = sequence(draft, live, at: start),
                isClause(
                    draft, live, position: live.firstIndex(of: start) ?? 0, starts: starts,
                    after: found.length)
            else { return nil }
            return (index: index, value: found.value, kind: found.kind)
        }
        guard let head = candidates.firstIndex(where: { $0.value == 1 }), candidates.count - head >= 2
        else { return [] }
        let kind = candidates[head].kind
        let run = Array(candidates[head...])
        guard
            run.enumerated().allSatisfy({ offset, candidate in
                candidate.kind == kind && candidate.value == offset + 1
            }), run.last?.value == candidates.count - head
        else { return [] }
        return run.map { starts[$0.index] }
    }

    /// Takes the sequence word off an item, capitalises what is left of it and drops its full stop, answering its mark.
    private static func itemise(
        _ draft: inout Draft, _ opening: Int, items: [Int], item: Int, ordinal: Bool
    ) -> String? {
        let live = draft.presentIndices
        guard let position = live.firstIndex(of: opening) else { return nil }
        let length: Int
        if ordinal {
            length = 1
        } else {
            guard let found = sequence(draft, live, at: opening) else { return nil }
            length = found.length
        }
        for index in live[position..<position + length] { draft.remove(at: index, by: id) }
        let end = item + 1 < items.count ? items[item + 1] : draft.words.count
        let body = draft.presentIndices.filter { $0 >= opening && $0 < end }
        guard let head = body.first, let tail = body.last else { return nil }
        draft.replace(at: head, with: WordShape.capitalised(draft.words[head].text), by: id)
        draft.replace(at: tail, with: WordShape.withoutTrailingStop(draft.words[tail].text), by: id)
        return draft.presentIndices.first == head ? Draft.bullet : "\n" + Draft.bullet
    }

    /// The sequence word a piece opens with — "first", "two", "number three", "point four" — and how many words it took.
    private static func sequence(
        _ draft: Draft, _ live: [Int], at word: Int
    ) -> (value: Int, kind: SequenceKind, length: Int)? {
        guard let position = live.firstIndex(of: word) else { return nil }
        var length = 0
        if position + 1 < live.count, Self.prefixes.contains(draft.shape(at: live[position]).key) {
            length = 1
        }
        guard position + length < live.count else { return nil }
        let prefix = length == 0 ? nil : draft.shape(at: live[position]).key
        let head = draft.shape(at: live[position + length])
        if let value = Self.ordinals[head.key] {
            guard prefix != nil || head.endsClause else { return nil }
            return (value, .ordinal, length + 1)
        }
        // A bare cardinal counts the words after it as readily as it announces an item — "one bug is still open" — so it needs the announcing word or the mark the speaker set it off with.
        guard length > 0 || head.endsClause else { return nil }
        // A point-number needs a clause mark to distinguish a list item from a decimal.
        guard prefix != "point" || head.endsClause else { return nil }
        if let value = Self.cardinals[head.key] { return (value, .cardinal, length + 1) }
        return nil
    }

    /// Whether what a piece says after its sequence word stands as a clause rather than naming a thing.
    private static func isClause(
        _ draft: Draft, _ live: [Int], position opening: Int, starts: [Int], after head: Int
    )
        -> Bool
    {
        let openingWord = live[opening]
        let endWord = starts.first(where: { $0 > openingWord }) ?? draft.words.count
        let body = live[(opening + head)..<live.count].prefix { $0 < endWord }
        guard body.count >= 2, let first = body.first else { return false }
        return !Self.determiners.contains(draft.shape(at: first).key)
    }

    // MARK: Paragraphs between topics

    /// Whether a piece opens on a new topic — an ordinal item, or a phrase a speaker moves on with.
    private static func opensTopic(_ draft: Draft, at word: Int) -> Bool {
        let live = draft.presentIndices
        guard let position = live.firstIndex(of: word) else { return false }
        let ordinalPosition: Int
        if Self.ordinals[draft.shape(at: live[position]).key] != nil {
            ordinalPosition = position
        } else if position + 1 < live.count,
            Self.prefixes.contains(draft.shape(at: live[position]).key),
            Self.ordinals[draft.shape(at: live[position + 1]).key] != nil
        {
            ordinalPosition = position + 1
        } else {
            ordinalPosition = -1
        }
        if ordinalPosition >= 0, ordinalPosition + 1 < live.count,
            !Self.determiners.contains(draft.shape(at: live[ordinalPosition + 1]).key)
        {
            return true
        }
        return Self.topics.contains { phrase in
            position + phrase.count <= live.count
                && zip(phrase, live[position..<position + phrase.count]).allSatisfy {
                    $0 == draft.shape(at: $1).key
                }
        }
    }

    // MARK: The words this reads

    /// Whether a sequence is counted in ordinals or in cardinals; one dictation's list never mixes them.
    private enum SequenceKind { case ordinal, cardinal }

    /// Words that may stand before the number of an item, as in "number one" and "point two".
    private static let prefixes: Set<String> = ["number", "point", "item", "step"]

    private static let ordinals: [String: Int] = [
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7,
        "eighth": 8, "ninth": 9, "tenth": 10,
    ]

    private static let cardinals: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "1": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7, "8": 8,
        "9": 9, "10": 10,
    ]

    /// The phrases a speaker opens a new topic with after a pause.
    private static let topics: [[String]] = [
        ["okay", "so"], ["ok", "so"], ["another", "thing"], ["one", "more", "thing"],
        ["moving", "on"], ["also"], ["next"], ["finally"], ["anyway"], ["additionally"],
        ["furthermore"], ["lastly"],
    ]
}

struct SeamSnippetInput: Sendable {
    let text: String
    let removableStops: [Int]
    let source: String

    func removingSeamStops() -> String {
        var result = source
        for index in removableStops.reversed() where index < result.count {
            result.remove(at: result.index(result.startIndex, offsetBy: index))
        }
        return result
    }

    func restoringUnconsumedStops(in expanded: ExpandedTranscript) -> ExpandedTranscript {
        guard expanded.text != source else { return .unchanged(text) }
        let expandedChars = Array(expanded.text)
        var result = ""
        var inputOffset = 0
        var stopOffsets = Set(removableStops)
        for _ in source {
            if stopOffsets.remove(inputOffset) != nil {
                if inputOffset < expandedChars.count,
                    expandedChars[inputOffset].isWhitespace || expandedChars[inputOffset].isNewline
                {
                    result.append(".")
                }
            } else if inputOffset < expandedChars.count {
                result.append(expandedChars[inputOffset])
            }
            inputOffset += 1
        }
        result += expandedChars.dropFirst(min(inputOffset, expandedChars.count))
        return ExpandedTranscript(text: result, snippets: expanded.snippets)
    }
}

extension DictationCorrection {
    /// The same correction, indexing words `offset` further into a longer sentence.
    fileprivate func shifted(by offset: Int) -> Self {
        Self(
            heard: heard, wrote: wrote,
            wordRange: (wordRange.lowerBound + offset)..<(wordRange.upperBound + offset),
            entryID: entryID, reason: reason, heardConfidence: heardConfidence)
    }
}

extension String {
    /// How many words were spoken, counted the way the corrections' ranges count them.
    var spokenWordCount: Int { split(whereSeparator: \.isWhitespace).count }
}
