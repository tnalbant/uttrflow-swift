public import UttrflowCore
import UttrflowDictionary

// The verdict on a rewrite, and the guard that reaches it.
/// Whether a rewrite may be shown to the user.
public enum GuardVerdict: Sendable, Equatable {
    /// The rewrite may be shown.
    case accepted
    /// The rewrite is refused, with the reason a log can show and the kind a pasted report may carry.
    case rejected(reason: String, kind: RefusalKind)

    public var isAccepted: Bool { self == .accepted }
}

/// Checks that a model tidied the words rather than replacing them. See Docs/ai-model-output.md.
public struct MeaningPreservationGuard: Sendable {
    /// A rewrite may grow — punctuation, expanded contractions — but not by this much.
    private static let maximumGrowthFactor = 2.0
    /// Below this fraction of the original words the model replaced rather than tidied.
    private static let minimumRetainedFraction = 0.4
    /// Utterances this short skip the retention floor ("um yes" to "Yes."); at six, "Paris" slipped through.
    private static let shortUtteranceWords = 3

    /// Openings that mean the model is chatting rather than tidying.
    private static let preambles = [
        "here is", "here's", "sure,", "certainly", "of course", "i've", "i have",
        "the corrected", "the cleaned", "cleaned:", "output:", "result:",
    ]

    /// Makes a guard; it holds no state.
    public init() {}

    /// Judges the rewrite against the kept words, the words a pass took out beyond its grant, the readings offered, the echo a pass took back, and the layout allowed.
    public func verdict(
        draft: Draft, rewritten: String, offering doubtful: [DoubtfulSpan] = [], echoed: String = "",
        layout: LayoutPolicy = [.paragraphs, .lists],
        grammar: GrammarPolicy = .repair,
        grants: [PassID: RemovalGrant] = CleaningPipeline.standard.grants
    ) -> GuardVerdict {
        let rewritten = Self.respellingClockTimes(rewritten, as: draft.text)
        let excusingPreamble = Self.rewriteStartsWithOfferedReading(
            draft: draft, rewritten: rewritten, offering: doubtful)
        if case .rejected(let reason, let kind) = Self.textVerdict(
            original: draft.text, rewritten: rewritten, excusingPreamble: excusingPreamble)
        {
            return .rejected(reason: reason, kind: kind)
        }
        if case .rejected(let reason, let kind) = Self.spokenPunctuationVerdict(
            draft: draft, rewritten: rewritten)
        {
            return .rejected(reason: reason, kind: kind)
        }
        let restored = Self.restored(RemovalAudit.unauthorised(in: draft, grants: grants))
        if case .rejected(let reason, let kind) = Self.removalVerdict(
            restored, kept: draft.text, rewritten: rewritten, echoed: echoed)
        {
            return .rejected(reason: reason, kind: kind)
        }
        let alignment = RewriteAlignment(kept: draft.text, rewritten: rewritten)
        let readings = Self.readingVerdict(doubtful, in: alignment)
        if case .rejected(let reason, let kind) = readings.verdict {
            return .rejected(reason: reason, kind: kind)
        }
        if case .rejected(let reason, let kind) = Self.confidentHomophoneVerdict(draft, aligned: alignment) {
            return .rejected(reason: reason, kind: kind)
        }
        if case .rejected(let reason, let kind) = Self.layoutVerdict(
            kept: draft.text, rewritten: rewritten, layout: layout)
        {
            return .rejected(reason: reason, kind: kind)
        }
        return Self.grammarVerdict(
            alignment, excusing: readings.excused, echoed: echoed, allowing: doubtful,
            restoring: restored.map(\.token), policy: grammar)
    }

    /// Allows a chat-like opening only when it is the offered reading of the doubtful first run.
    private static func rewriteStartsWithOfferedReading(
        draft: Draft, rewritten: String, offering doubtful: [DoubtfulSpan]
    ) -> Bool {
        guard let first = doubtful.first,
            let heard = draft.text.range(of: first.heard, options: [.caseInsensitive]),
            draft.text[..<heard.lowerBound].allSatisfy(\.isWhitespace),
            first.candidates.contains(where: { candidate in
                rewritten.range(of: candidate.spelling, options: [.caseInsensitive, .anchored]) != nil
            })
        else { return false }
        return true
    }

    /// Refuses a rewrite that drops or substitutes punctuation a pass wrote from spoken instructions.
    static func spokenPunctuationVerdict(draft: Draft, rewritten: String) -> GuardVerdict {
        let marks = Set(SpokenPunctuationPass.marks.flatMap { Array($0.mark) } + Array("()[]{}"))
        var required: [Character: Int] = [:]
        for word in draft.words {
            for edit in word.edits where edit.by == .spokenPunctuation && edit.kind == .replaced {
                guard !edit.to.contains("@") else { continue }
                for mark in marks {
                    let added = edit.to.filter { $0 == mark }.count - edit.from.filter { $0 == mark }.count
                    if added > 0 { required[mark, default: 0] += added }
                }
            }
        }
        for (mark, count) in required where rewritten.filter({ $0 == mark }).count < count {
            return .rejected(
                reason: "the rewrite dropped a spoken punctuation mark", kind: .layout)
        }
        return .accepted
    }

    /// Refuses a sound-alike substitution when the recogniser was sure of the kept word.
    private static func confidentHomophoneVerdict(_ draft: Draft, aligned: RewriteAlignment) -> GuardVerdict {
        guard draft.confidencesAreReal else { return .accepted }
        let heard = draft.words
            .filter { $0.isPresent && !$0.isLayoutMark && !$0.heard.isEmpty }
            .flatMap { word in grammarTokens(word.text).map { (token: $0, confidence: word.confidence) } }
        for change in aligned.changes {
            for index in change.kept where index < heard.count {
                let token = aligned.kept[index]
                guard heard[index].confidence >= WordCorrectionEngine.certaintyThreshold else { continue }
                if change.rewritten.contains(where: {
                    Homophones.share(token.matching, aligned.rewritten[$0].matching)
                }) {
                    return .rejected(
                        reason: "the rewrite replaced high-confidence '\(token.text)' with a sound-alike",
                        kind: .lostWord)
                }
            }
        }
        return .accepted
    }

    /// The content words and negations among removals no grant covers, each with the pass that took it.
    static func restored(_ removals: [UnauthorisedRemoval]) -> [(pass: PassID, token: GrammarToken)] {
        removals.flatMap { removal in
            grammarTokens(removal.text)
                .filter { $0.isPlain && (isContent($0) || isNegation($0.matching)) }
                .map { (removal.pass, $0) }
        }
    }

    /// Refuses a rewrite that leaves out a word a pass removed without the grant to, since the passes alone cannot answer for it.
    static func removalVerdict(
        _ restored: [(pass: PassID, token: GrammarToken)], kept: String, rewritten: String, echoed: String
    ) -> GuardVerdict {
        let written = (grammarTokens(echoed) + grammarTokens(rewritten)).filter(\.isPlain)
        var negations = negators(in: grammarTokens(kept))
        let romanisedHindiContext = hasRomanisedHindiContext(grammarTokens(kept) + written)
        for (pass, token) in restored {
            let negates = Self.isNegation(token.matching)
            if negates { negations += 1 }
            let present =
                negates
                ? negators(in: written) >= negations
                : written.contains {
                    survives(token.matching, as: $0, allowingRomanisedHindiSpellings: romanisedHindiContext)
                }
            guard present else {
                return .rejected(
                    reason: "the \(pass) step took out '\(token.text)' and the rewrite does not put it back",
                    kind: .removedWordNotRestored)
            }
        }
        return .accepted
    }

    /// The readings the rewrite wrote where a doubtful run stood, so the entries that taught them are counted used.
    public func readingsTaken(
        draft: Draft, rewritten: String, offering doubtful: [DoubtfulSpan]
    ) -> [Reading] {
        guard !doubtful.isEmpty else { return [] }
        return Self.readingVerdict(doubtful, in: RewriteAlignment(kept: draft.text, rewritten: rewritten))
            .taken
    }

    /// A doubtful run may be written where it stands as it was heard or as a reading offered for it, inflected or not, and as nothing else.
    static func readingVerdict(
        _ doubtful: [DoubtfulSpan], in alignment: RewriteAlignment
    ) -> (verdict: GuardVerdict, excused: Set<Int>, taken: [Reading]) {
        var excused: Set<Int> = []
        var taken: [Reading] = []
        guard !doubtful.isEmpty else { return (.accepted, excused, taken) }
        for span in doubtful {
            for place in alignment.keptRuns(spelled: DoubtfulSpan.closedUp(span.heard)) {
                let touched = alignment.changes.filter { $0.kept.overlaps(place) }
                // A run the rewrite left where it stood is the run as it was heard, and needs no reading.
                guard let first = touched.first, let last = touched.last else { continue }
                let start = min(place.lowerBound, first.kept.lowerBound)
                let end = max(place.upperBound, last.kept.upperBound)
                // A change reaching past the run took its neighbours with it, so they are expected here too.
                let before = alignment.keptSpelling(of: start..<place.lowerBound)
                let after = alignment.keptSpelling(of: place.upperBound..<end)
                // The rewrite may inflect the run it was given — "payment sheets" for "payment sheet" — and change it no further.
                func writes(_ reading: String) -> Bool {
                    let wanted = DoubtfulSpan.closedUp(reading)
                    return WordForms.inflections(of: wanted).union([wanted]).map { before + $0 + after }
                        .contains(alignment.standing(in: start..<end))
                }
                let offered = span.candidates.filter { writes($0.spelling) }
                guard writes(span.heard) || !offered.isEmpty else {
                    return (
                        .rejected(
                            reason: "the rewrite read '\(span.heard)' as a word it was not offered",
                            kind: .unofferedReading),
                        excused, taken
                    )
                }
                if let reading = Self.reading(
                    among: offered, heard: span.heard, standing: alignment.standingAsWritten(in: start..<end))
                {
                    taken.append(reading)
                }
                // A reading rightly written here is the one substitution the survival check must let past.
                for change in touched { excused.formUnion(change.kept.clamped(to: place)) }
            }
        }
        return (.accepted, excused, taken)
    }

    /// The offered reading written in the run's place, told from the heard words by its capitals and spaces when it closes up alike.
    private static func reading(
        among offered: [Reading], heard: String, standing written: String
    ) -> Reading? {
        let asHeard = RewriteAlignment.asWritten(heard)
        return offered.first { reading in
            let spelled = RewriteAlignment.asWritten(reading.spelling)
            // Capitals alone are what a sentence gives its first word, so they are no sign the model chose the reading.
            guard spelled.lowercased() != asHeard.lowercased() else { return false }
            return written.contains(spelled)
        }
    }

    /// The same judgement over two texts, which is how a test states one.
    static func candidateVerdict(
        _ doubtful: [DoubtfulSpan], kept: String, rewritten: String
    ) -> GuardVerdict {
        readingVerdict(doubtful, in: RewriteAlignment(kept: kept, rewritten: rewritten)).verdict
    }

    /// Whether a reading is written out as whole words: `PaymentSheet` or "payment sheets" for "payment sheet", never "our time" inside "four times".
    static func isWritten(_ reading: String, in rewritten: String) -> Bool {
        let wanted = DoubtfulSpan.closedUp(reading)
        guard !wanted.isEmpty else { return false }
        let (written, begins, ends) = closedUpEdges(rewritten)
        // The rewrite may inflect the run it was given — "payment sheets" for "payment sheet" — and change it no further.
        let forms = WordForms.inflections(of: wanted).union([wanted])
        return begins.contains { start in
            forms.contains { form in
                let end = start + form.count
                return end <= written.count && ends.contains(end)
                    && String(written[start..<end]) == form
            }
        }
    }

    /// A text closed up, with the places a word begins and ends, reading a camel hump as an edge like `spelledInto`.
    static func closedUpEdges(_ text: String) -> (written: [Character], begins: Set<Int>, ends: Set<Int>) {
        var written: [Character] = []
        var begins: Set<Int> = []
        var ends: Set<Int> = [0]
        var previous: Character?
        for character in text {
            guard character.isLetter || character.isNumber else {
                previous = character
                continue
            }
            // A word opens at the start, after anything that is not a letter, and at a capital.
            if (previous.map { !$0.isLetter } ?? true) || character.isUppercase {
                begins.insert(written.count)
                ends.insert(written.count)
            }
            if !character.isLetter { ends.insert(written.count) }  // A digit closes the word before it.
            written += DoubtfulSpan.closedUp(String(character))
            previous = character
        }
        ends.insert(written.count)
        return (written, begins, ends)
    }

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

    // MARK: Grammar

    /// A word of the kept draft or the rewrite, carrying what the grammar checks need to classify it.
    struct GrammarToken: Sendable, Equatable {
        /// The word as written, punctuation trimmed from its edges.
        let text: String
        /// Lowercased with curly apostrophes straightened, the form the function-word set is keyed by.
        let lookup: String
        /// Lowercased with curly apostrophes straightened, the exact spelling used for survival checks.
        let matching: String
        /// Whether the word opens the text or follows a sentence-closing mark.
        let startsSentence: Bool

        /// Whether the checks can read the word at all: Latin script, accents included; Devanagari and the like are left to the base checks.
        var isPlain: Bool { matching.unicodeScalars.allSatisfy(Self.isLatin) }

        /// Whether a scalar is ASCII, a Latin letter with or without its accent, or an accent written apart.
        static func isLatin(_ scalar: Unicode.Scalar) -> Bool {
            switch scalar.value {
            case 0x00...0x7F: true
            case 0x00C0...0x024F, 0x1E00...0x1EFF: scalar.properties.isAlphabetic
            case 0x0300...0x036F: true
            default: false
            }
        }
    }

    /// A repair may change a word's form, never which content words are there, either way round, or the order they came in. See `Docs/cleanup.md`.
    static func grammarVerdict(
        kept: String, rewritten: String, allowing doubtful: [DoubtfulSpan] = [], echoed: String = ""
    ) -> GuardVerdict {
        let alignment = RewriteAlignment(kept: kept, rewritten: rewritten)
        return grammarVerdict(
            alignment, excusing: readingVerdict(doubtful, in: alignment).excused, echoed: echoed,
            allowing: doubtful)
    }

    /// The same check over an alignment already in hand, each word judged against what stands in its own place.
    static func grammarVerdict(
        _ alignment: RewriteAlignment, excusing excused: Set<Int>, echoed: String,
        allowing doubtful: [DoubtfulSpan], restoring restored: [GrammarToken] = [],
        policy: GrammarPolicy = .repair
    ) -> GuardVerdict {
        if policy == .asSpoken, case .rejected(let reason, let kind) = asSpokenFormVerdict(alignment) {
            return .rejected(reason: reason, kind: kind)
        }
        let keptTokens = alignment.kept
        let rewrittenTokens = alignment.rewritten
        let echoTokens = grammarTokens(echoed)
        // The echo the caret pass took back opened the model's answer, so its words count as survivors ahead of the rest.
        let written = (echoTokens + rewrittenTokens).filter(\.isPlain)
        let romanisedHindiContext = hasRomanisedHindiContext(keptTokens + rewrittenTokens + echoTokens)
        // A number spoken over several words answers to the one numeral the rewrite wrote for it.
        let composed = composedNumbers(keptTokens, in: Set(written.map(\.matching)))
        let removable = removableSpeechArtifacts(in: alignment)
        let carried = keptTokens.indices.filter { index in
            let token = keptTokens[index]
            return token.isPlain
                && (isContent(token) || FunctionWords.isMeaningBearing(token.lookup)
                    || isAcronymLetter(at: index, in: keptTokens))
                && !composed.contains(index) && !excused.contains(index) && !removable.contains(index)
        }
        if case .rejected(let reason, let kind) = wordOrderVerdict(kept: keptTokens, written: written) {
            return .rejected(reason: reason, kind: kind)
        }
        if case .rejected(let reason, let kind) = survivalVerdict(
            carried.map { keptTokens[$0] }, in: written,
            allowingRomanisedHindiSpellings: romanisedHindiContext)
        {
            return .rejected(reason: reason, kind: kind)
        }
        if case .rejected(let reason, let kind) = placeVerdict(
            Set(carried), in: alignment, echo: echoTokens,
            allowingRomanisedHindiSpellings: romanisedHindiContext)
        {
            return .rejected(reason: reason, kind: kind)
        }
        if case .rejected(let reason, let kind) = casePreservationVerdict(alignment) {
            return .rejected(reason: reason, kind: kind)
        }
        let dropped = negators(in: keptTokens) - negators(in: rewrittenTokens + echoTokens)
        if dropped > 0 {
            return .rejected(reason: "the rewrite dropped a negation", kind: .negationDropped)
        }
        if case .rejected(let reason, let kind) = negationPlacementVerdict(
            alignment, echo: echoTokens)
        {
            return .rejected(reason: reason, kind: kind)
        }
        // The echo is the field's text before the caret, so it is an origin a negation may come from, never a total.
        let added =
            negators(in: rewrittenTokens) - negators(in: keptTokens) - negators(in: echoTokens + restored)
        if added > 0 {
            return .rejected(reason: "the rewrite added a negation", kind: .negationAdded)
        }
        let churn = alignedFunctionWordChurn(alignment)
        if churn > 3 * sentenceCount(alignment.rewrittenText) {
            return .rejected(reason: "the rewrite changed \(churn) small words", kind: .smallWordChurn)
        }
        // A word put back where a pass took it without the grant to is the speaker's, not the model's.
        return inventionVerdict(
            alignment, echo: echoTokens + restored, allowing: doubtful,
            allowingRomanisedHindiSpellings: romanisedHindiContext)
    }

    /// Refuses a kept word whose regular or reviewed irregular form changed in an as-spoken destination.
    private static func asSpokenFormVerdict(_ alignment: RewriteAlignment) -> GuardVerdict {
        for change in alignment.changes {
            for kept in alignment.kept[change.kept] {
                for rewritten in alignment.rewritten[change.rewritten]
                where kept.matching != rewritten.matching {
                    let keptIrregular = Self.asSpokenIrregularForms[kept.matching]
                    let rewrittenIrregular = Self.asSpokenIrregularForms[rewritten.matching]
                    guard
                        WordForms.sameForm(kept.matching, rewritten.matching)
                            || (keptIrregular != nil && keptIrregular == rewrittenIrregular)
                    else { continue }
                    return .rejected(reason: "the rewrite changed a kept word's form", kind: .lostWord)
                }
            }
        }
        return .accepted
    }

    /// Reviewed irregular paradigms whose forms must stay as spoken in destinations that do not repair grammar.
    private static let asSpokenIrregularForms: [String: String] = Dictionary(
        uniqueKeysWithValues: [
            ("be", ["am", "is", "are", "was", "were", "been", "being"]),
            ("see", ["saw", "seen"]),
            ("come", ["came"]),
        ].flatMap { root, forms in
            ([root] + forms).map { ($0, root) }
        })

    /// Finds words a cleanup pass could remove or turn into punctuation in a changed run.
    private static func removableSpeechArtifacts(in alignment: RewriteAlignment) -> Set<Int> {
        let kept = alignment.kept
        var removable = Set(kept.indices.filter { FillersPass.fillerWords.contains(kept[$0].matching) })
        let keptGaps = grammarTokenGaps(alignment.keptText)
        let rewrittenGaps = grammarTokenGaps(alignment.rewrittenText)
        guard keptGaps.count == kept.count + 1, rewrittenGaps.count == alignment.rewritten.count + 1
        else { return removable }
        // The draft the passes read, so a name the spoken-punctuation pass judged a mention is judged the same here.
        let draft = Draft(
            words: kept.indices.map { Draft.Word(kept[$0].text + keptGaps[$0 + 1]) })
        for mark in Set(SpokenPunctuationPass.marks.map(\.mark)) {
            guard let character = mark.first, String(character) == mark else { continue }
            let names = SpokenPunctuationPass.marks.filter { $0.mark == mark }
                .sorted { $0.words.count > $1.words.count }
            for change in alignment.changes {
                var remaining =
                    addedMarks(character, in: change, keptGaps: keptGaps, rewrittenGaps: rewrittenGaps)
                for (name, _, kind) in names where remaining > 0 {
                    guard name.count <= change.kept.count else { continue }
                    for start in change.kept where remaining > 0 {
                        let end = start + name.count
                        guard end <= change.kept.upperBound,
                            zip(name, kept[start..<end]).allSatisfy({ $0 == $1.matching }),
                            !removable.contains(where: { start..<end ~= $0 }),
                            !MentionGuard.isMentioned(
                                at: start, spanning: name.count, in: Array(kept.indices), of: draft,
                                reach: MentionGuard.phraseReach, kind: kind)
                        else { continue }
                        removable.formUnion(start..<end)
                        remaining -= 1
                    }
                }
            }
        }
        return removable
    }

    /// Marks a changed run's rewrite has beyond its draft, counted at its edges and between its words, the text's closing stop only for a name that closed the draft.
    private static func addedMarks(
        _ character: Character, in change: RewriteAlignment.Change, keptGaps: [String],
        rewrittenGaps: [String]
    ) -> Int {
        let count: (ArraySlice<String>) -> Int = { $0.joined().filter { $0 == character }.count }
        var written = count(rewrittenGaps[change.rewritten.lowerBound...change.rewritten.upperBound])
        // A closing mark at the very end answers a spoken name only when that name ended the draft too.
        if change.rewritten.upperBound == rewrittenGaps.count - 1,
            change.kept.upperBound < keptGaps.count - 1, ".!?".contains(character),
            rewrittenGaps[rewrittenGaps.count - 1].contains(character)
        {
            written -= 1
        }
        return written - count(keptGaps[change.kept.lowerBound...change.kept.upperBound])
    }

    /// Refuses a carried word that a changed run lost, judging it only against the words standing in that run's place.
    static func placeVerdict(
        _ carried: Set<Int>, in alignment: RewriteAlignment, echo: [GrammarToken],
        allowingRomanisedHindiSpellings: Bool = false
    ) -> GuardVerdict {
        for change in alignment.changes {
            let here = (alignment.rewritten[change.rewritten] + echo).filter(\.isPlain)
            let tokens = change.kept.compactMap { index in
                carried.contains(index) ? alignment.kept[index] : nil
            }
            if case .rejected(let reason, let kind) = survivalVerdict(
                tokens, in: here, allowingRomanisedHindiSpellings: allowingRomanisedHindiSpellings)
            {
                return .rejected(reason: reason, kind: kind)
            }
        }
        return .accepted
    }

    /// Refuses a content word the model brought in, an addition being the same fault as a loss read the other way.
    static func inventionVerdict(
        kept: [GrammarToken], rewritten: [GrammarToken], echo: [GrammarToken],
        allowing doubtful: [DoubtfulSpan]
    ) -> GuardVerdict {
        inventionVerdict(
            RewriteAlignment(
                kept: kept.map(\.text).joined(separator: " "),
                rewritten: rewritten.map(\.text).joined(separator: " ")),
            echo: echo, allowing: doubtful)
    }

    /// Refuses a content or meaning-bearing word with no origin in the same aligned run or an offered reading for it.
    static func inventionVerdict(
        _ alignment: RewriteAlignment, echo: [GrammarToken], allowing doubtful: [DoubtfulSpan],
        allowingRomanisedHindiSpellings: Bool? = nil
    ) -> GuardVerdict {
        // A draft the checks cannot read romanises into words with no counterpart here, so the base checks keep it.
        guard alignment.kept.allSatisfy(\.isPlain) else { return .accepted }
        let romanisedHindiContext =
            allowingRomanisedHindiSpellings
            ?? hasRomanisedHindiContext(alignment.kept + alignment.rewritten + echo)
        let origins = (alignment.kept + echo).filter(\.isPlain)
        let originIndex = WordOccurrenceIndex(origins)
        var usedOrigins = Set<Int>()
        var usedReadings = Set<Int>()
        for index in alignment.rewritten.indices
        where alignment.rewritten[index].isPlain
            && (isContent(alignment.rewritten[index])
                || FunctionWords.isMeaningBearing(alignment.rewritten[index].lookup))
        {
            let token = alignment.rewritten[index]
            if let origins = originIndex.matchingOrigins(
                token, allowingRomanisedHindiSpellings: romanisedHindiContext,
                excluding: usedOrigins)
            {
                usedOrigins.formUnion(origins)
                continue
            }
            let offeredReading = doubtful.enumerated().first { entry in
                let (spanIndex, span) = entry
                guard !usedReadings.contains(spanIndex) else { return false }
                return alignment.keptRuns(spelled: DoubtfulSpan.closedUp(span.heard)).contains { source in
                    alignment.changes.contains { change in
                        change.kept.overlaps(source) && change.rewritten.contains(index)
                            && span.candidates.contains { survivesCandidate(token, candidate: $0.spelling) }
                    }
                }
            }
            if let offeredReading {
                usedReadings.insert(offeredReading.offset)
            } else {
                return .rejected(reason: "the rewrite invented '\(token.text)'", kind: .inventedWord)
            }
        }
        return .accepted
    }

    /// Matches one offered spelling without treating a substring or unrelated occurrence as provenance.
    private static func survivesCandidate(_ token: GrammarToken, candidate: String) -> Bool {
        let parts = grammarTokens(candidate)
        return parts.count == 1 && survives(parts[0].matching, as: token)
    }

    /// Counts changed function words inside aligned runs, so a swap cannot cancel against another sentence.
    static func alignedFunctionWordChurn(_ alignment: RewriteAlignment) -> Int {
        alignment.changes.reduce(0) { total, change in
            let before = alignment.kept[change.kept].filter { $0.isPlain && !isContent($0) }
            let after = alignment.rewritten[change.rewritten].filter { $0.isPlain && !isContent($0) }
            return total + functionWordChurn(before, after)
        }
    }

    /// Refuses to erase capitals that distinguish a mid-sentence name or acronym from an ordinary word.
    static func casePreservationVerdict(_ alignment: RewriteAlignment) -> GuardVerdict {
        var required: [String: [String: Int]] = [:]
        for token in alignment.kept where !token.startsSentence && token.text.contains(where: \.isUppercase) {
            required[token.matching, default: [:]][token.text, default: 0] += 1
        }
        var written: [String: [String: Int]] = [:]
        for token in alignment.rewritten {
            written[token.matching, default: [:]][token.text, default: 0] += 1
        }
        for (matching, spellings) in required
        where (written[matching]?.values.reduce(0, +) ?? 0) >= spellings.values.reduce(0, +) {
            for (spelling, count) in spellings where (written[matching]?[spelling] ?? 0) < count {
                return .rejected(
                    reason: "the rewrite changed the capitalization of '\(spelling)'", kind: .lostWord)
            }
        }
        return .accepted
    }

    /// Refuses a negator that moved to a different content-word neighbourhood, while allowing contractions and punctuation changes.
    static func negationPlacementVerdict(
        _ alignment: RewriteAlignment, echo: [GrammarToken]
    ) -> GuardVerdict {
        let kept = alignment.kept
        let rewritten = alignment.rewritten
        // Non-Latin negations are commonly romanised by the cleanup model; their existing count check remains authoritative.
        let keptNegations = kept.indices.filter {
            kept[$0].isPlain && isNegation(kept[$0].matching)
        }
        guard !keptNegations.isEmpty else { return .accepted }
        let written = rewritten + echo
        let writtenNegations = written.indices.filter {
            written[$0].isPlain && isNegation(written[$0].matching)
        }
        guard keptNegations.count == writtenNegations.count else { return .accepted }

        let keptPlaces = negationPlaces(in: kept)
        let rewrittenPlaces = negationPlaces(in: rewritten)
        guard keptPlaces.count == rewrittenPlaces.count else { return .accepted }
        guard
            zip(keptPlaces, rewrittenPlaces).allSatisfy({ original, answer in
                original.clause == answer.clause
                    && sameAnchor(original.before, answer.before)
                    && sameAnchor(original.after, answer.after)
            })
        else {
            return .rejected(reason: "the rewrite moved a negation", kind: .negationMoved)
        }
        return .accepted
    }

    /// The clause and its nearest content words around one negation.
    private struct NegationPlace {
        let clause: Int
        let before: GrammarToken?
        let after: GrammarToken?
    }

    /// Whether a neighbouring word survived as the same word or inside an identifier.
    private static func sameAnchor(_ first: GrammarToken?, _ second: GrammarToken?) -> Bool {
        switch (first, second) {
        case (nil, nil): return true
        case (let first?, let second?):
            return survives(first.matching, as: second) || survives(second.matching, as: first)
        default: return false
        }
    }

    /// Coordinators bound clauses; the content words beside a negation locate its scope.
    private static func negationPlaces(in tokens: [GrammarToken]) -> [NegationPlace] {
        var clause = 0
        var clauseStart = 0
        var result: [NegationPlace] = []
        for index in tokens.indices where tokens[index].isPlain {
            let token = tokens[index]
            if ["but", "and", "or"].contains(token.matching) {
                clause += 1
                clauseStart = index
            }
            if isNegation(token.matching) {
                let clauseEnd =
                    tokens[(index + 1)...].firstIndex {
                        ["but", "and", "or"].contains($0.matching)
                    } ?? tokens.endIndex
                let before = tokens[clauseStart..<index].last(where: isAnchor)
                let after = tokens[(index + 1)..<clauseEnd].first(where: isAnchor)
                result.append(NegationPlace(clause: clause, before: before, after: after))
            }
        }
        return result
    }

    /// Negations and function words do not identify the proposition a negation belongs to.
    private static func isAnchor(_ token: GrammarToken) -> Bool {
        token.isPlain && !isNegation(token.matching) && !FunctionWords.holds(token.lookup)
    }

    /// Whether an identifier is spelled wholly from said words, every part of it one of them and in the order they were said.
    static func isSpelled(_ identifier: String, from said: [GrammarToken]) -> Bool {
        let parts = identifierParts(identifier)
        guard parts.count > 1 else { return false }
        var next = said.startIndex
        for part in parts {
            guard let place = said[next...].firstIndex(where: { survives(part, as: $0) }) else {
                return false
            }
            next = place + 1
        }
        return true
    }

    /// The words an identifier is written from, cut at a camel hump and at anything not a letter or digit.
    static func identifierParts(_ identifier: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var previous: Character?
        for character in identifier where character != "'" && character != "\u{2019}" {
            guard character.isLetter || character.isNumber else {
                if !current.isEmpty { parts.append(current) }
                current = ""
                previous = nil
                continue
            }
            if character.isUppercase, previous.map({ $0.isLowercase || $0.isNumber }) == true {
                parts.append(current)
                current = ""
            }
            current += character.lowercased()
            previous = character
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }

    /// Splits on whitespace and hyphens, trimming punctuation and tracking sentence starts.
    static func grammarTokens(_ text: String) -> [GrammarToken] {
        var tokens: [GrammarToken] = []
        var startsSentence = true
        let pieces = withoutThousandsSeparators(text)
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "/" })
        for raw in pieces {
            let endsSentence = raw.contains { ".!?".contains($0) }
            let trimmed = raw.drop(while: { !$0.isLetter && !$0.isNumber })
            let word = trimmed.reversed().drop(while: { !$0.isLetter && !$0.isNumber }).reversed()
            guard !word.isEmpty else {
                startsSentence = startsSentence || endsSentence
                continue
            }
            let lookup = String(word).lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
            tokens.append(
                GrammarToken(
                    text: String(word), lookup: lookup,
                    matching: lookup,
                    startsSentence: startsSentence))
            startsSentence = endsSentence
        }
        return joiningOneWordSpellings(tokens)
    }

    /// The text between the words `grammarTokens` reads, one more than there are words, so a mark is found at its place.
    static func grammarTokenGaps(_ text: String) -> [String] {
        var gaps = [""]
        var raw: [GrammarToken] = []
        let pieces = withoutThousandsSeparators(text)
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "/" })
        for piece in pieces {
            let leading = piece.prefix(while: { !$0.isLetter && !$0.isNumber })
            let trailing = String(
                piece.dropFirst(leading.count).reversed()
                    .prefix(while: { !$0.isLetter && !$0.isNumber }).reversed())
            guard leading.count < piece.count else {
                gaps[gaps.count - 1] += String(piece)
                continue
            }
            gaps[gaps.count - 1] += String(leading)
            raw.append(contentsOf: grammarTokens(String(piece)).prefix(1))
            gaps.append(trailing)
        }
        // A pair read as one word gives up the gap between its halves.
        var joined = [gaps[0]]
        var index = 0
        for token in grammarTokens(text) where index < raw.count {
            index += raw[index].matching == token.matching ? 1 : 2
            joined.append(gaps[min(index, gaps.count - 1)])
        }
        return joined
    }

    /// Two words written apart for one word, keyed by the one word; a listed pair, never a rule about shape.
    static let oneWordSpellings: [String: (first: String, second: String)] = [
        "cannot": ("can", "not")
    ]

    /// Reads a listed pair written apart as its one word, so "can not" and "cannot" are the same word either way round.
    static func joiningOneWordSpellings(_ tokens: [GrammarToken]) -> [GrammarToken] {
        var joined: [GrammarToken] = []
        var index = tokens.startIndex
        while index < tokens.endIndex {
            let token = tokens[index]
            let next = index + 1 < tokens.endIndex ? tokens[index + 1] : nil
            if let next, !next.startsSentence,
                let word = oneWordSpellings.first(where: {
                    $0.value.first == token.matching && $0.value.second == next.matching
                })?.key
            {
                joined.append(
                    GrammarToken(
                        text: token.text + next.text, lookup: word, matching: word,
                        startsSentence: token.startsSentence))
                index += 2
                continue
            }
            joined.append(token)
            index += 1
        }
        return joined
    }

    /// A number and a mid-sentence capital are always content; the rest is unless the set below holds it.
    static func isContent(_ token: GrammarToken) -> Bool {
        if token.matching.contains(where: \.isNumber) { return true }
        if !token.startsSentence, token.text.first?.isUppercase == true { return true }
        return !FunctionWords.holds(token.lookup)
    }

    /// Refuses a word the model moved, using the shared word alignment while leaving edits to the other guard checks.
    static func wordOrderVerdict(kept: [GrammarToken], written: [GrammarToken]) -> GuardVerdict {
        let alignment = WordErrorRate.measure(
            reference: kept.filter(\.isPlain).map(\.matching),
            hypothesis: written.filter(\.isPlain).map(\.matching))
        var deleted: Set<String> = []
        var inserted: Set<String> = []
        var substitutedFrom: Set<String> = []
        var substitutedTo: Set<String> = []
        for operation in alignment.alignment {
            switch operation {
            case .match:
                break
            case .deletion(let word):
                deleted.insert(word)
            case .insertion(let word):
                inserted.insert(word)
            case .substitution(let reference, let hypothesis):
                substitutedFrom.insert(reference)
                substitutedTo.insert(hypothesis)
            }
        }
        guard deleted.isDisjoint(with: inserted), substitutedFrom.isDisjoint(with: substitutedTo) else {
            return .rejected(reason: "the rewrite moved a word", kind: .movedWord)
        }
        return .accepted
    }

    /// Walks the kept content words along the rewrite, so a word may change its form but never its place.
    static func survivalVerdict(
        _ kept: [GrammarToken], in written: [GrammarToken], allowingRomanisedHindiSpellings: Bool = false
    ) -> GuardVerdict {
        var reached = 0
        var index = 0
        while index < kept.count {
            let token = kept[index]
            if index + 1 < kept.count, Self.symbolNames[kept[index + 1].matching] != nil {
                guard index + 2 < kept.count else {
                    return .rejected(
                        reason: "the rewrite lost or replaced '\(kept[index + 1].text)'", kind: .lostWord)
                }
                let symbol = kept[index + 1].matching
                let spelling =
                    Self.closedSpelling(token.text) + (Self.symbolNames[symbol] ?? "")
                    + Self.closedSpelling(kept[index + 2].text)
                if let range = Self.matchingSymbolSpelling(spelling, in: written, startingAt: reached) {
                    reached = range.upperBound
                    index += 3
                    continue
                }
            }
            if token.matching.count == 1, token.matching.first?.isLetter == true {
                var end = index
                var acronym = ""
                while end < kept.count, kept[end].matching.count == 1,
                    kept[end].matching.first?.isLetter == true
                {
                    acronym += kept[end].matching
                    end += 1
                }
                if acronym.count > 1,
                    let place = written.indices.first(where: {
                        $0 >= reached && written[$0].matching == acronym
                    })
                {
                    reached = place + 1
                    index = end
                    continue
                }
            }
            let matchingPlaces = written.indices.filter {
                survives(
                    token.matching, as: written[$0],
                    allowingRomanisedHindiSpellings: allowingRomanisedHindiSpellings)
            }
            guard !matchingPlaces.isEmpty else {
                return .rejected(reason: "the rewrite lost or replaced '\(token.text)'", kind: .lostWord)
            }
            // The earliest place still open is taken, which is the most room the words after it can be left.
            guard let place = matchingPlaces.first(where: { $0 >= reached }) else {
                return .rejected(reason: "the rewrite moved '\(token.text)'", kind: .movedWord)
            }
            reached = place
            index += 1
        }
        return .accepted
    }

    /// Keeps three or more adjacent spoken letter names together so articles like "a" can start an acronym.
    private static func isAcronymLetter(at index: Int, in tokens: [GrammarToken]) -> Bool {
        guard tokens[index].matching.count == 1, tokens[index].matching.first?.isLetter == true else {
            return false
        }
        var start = index
        while start > 0, tokens[start - 1].matching.count == 1,
            tokens[start - 1].matching.first?.isLetter == true
        {
            start -= 1
        }
        var end = index + 1
        while end < tokens.count, tokens[end].matching.count == 1,
            tokens[end].matching.first?.isLetter == true
        {
            end += 1
        }
        return end - start >= 3
    }

    /// Closes punctuation between adjacent spoken words when checking a symbol spelling.
    private static func closedSpelling(_ word: String) -> String {
        word.lowercased().filter(\.isLetter).description
    }

    /// Finds adjacent written tokens whose spelling includes the spoken symbol between its neighbours.
    private static func matchingSymbolSpelling(
        _ spelling: String, in written: [GrammarToken], startingAt start: Int
    ) -> Range<Int>? {
        guard !spelling.isEmpty else { return nil }
        for first in start..<written.count {
            var combined = ""
            for end in first..<written.count {
                combined += written[end].text.lowercased()
                if combined == spelling.lowercased() { return first..<(end + 1) }
                if combined.count >= spelling.count { break }
            }
        }
        return nil
    }

    /// Spoken punctuation names whose written marks join the words on either side.
    private static let symbolNames: [String: String] = [
        "dot": ".", "period": ".", "underscore": "_", "slash": "/", "backslash": "\\",
        "at": "@", "hyphen": "-", "dash": "-", "plus": "+", "hash": "#",
    ]

    /// Maps every spelling accepted by `survives` to its token positions, preserving their original order.
    private struct WordOccurrenceIndex {
        private let places: [String: [Int]]
        private let tokens: [GrammarToken]

        init(_ tokens: [GrammarToken]) {
            self.tokens = tokens
            var indexed: [String: [Int]] = [:]
            for (index, token) in tokens.enumerated() {
                var spellings: Set<String> = [token.matching]
                if let spoken = MeaningPreservationGuard.numberWordsByNumeral[token.matching] {
                    spellings.formUnion(spoken)
                }
                if let numeral = MeaningPreservationGuard.numberWords[token.matching] {
                    spellings.insert(numeral)
                }
                if let homophones = Homophones.group(containing: token.matching) {
                    spellings.formUnion(homophones)
                }
                if MeaningPreservationGuard.auxContractionRoots.contains(token.matching) {
                    spellings.insert("\(token.matching)nt")
                }
                if MeaningPreservationGuard.auxContractionRoots.contains(where: {
                    "\($0)nt" == token.matching
                }) {
                    spellings.insert(String(token.matching.dropLast(2)))
                }
                spellings.formUnion(Self.identifierSpellings(token.text))
                for spelling in spellings {
                    indexed[spelling, default: []].append(index)
                }
            }
            places = indexed
        }

        private static func identifierSpellings(_ identifier: String) -> Set<String> {
            let characters = Array(identifier)
            let lowered = Array(identifier.lowercased())
            guard lowered.count == characters.count else { return [] }
            var spellings: Set<String> = []
            for start in characters.indices {
                let opens = start == 0 || characters[start].isUppercase || !characters[start - 1].isLetter
                guard opens else { continue }
                for end in (start + 1)...characters.count {
                    let closes =
                        end == characters.count || characters[end].isUppercase || !characters[end].isLetter
                    if closes, end - start >= 3 {
                        spellings.insert(String(lowered[start..<end]))
                    }
                }
            }
            return spellings
        }

        func occurrences(of word: String) -> [Int] { places[word] ?? [] }

        func firstOccurrence(of word: String, atOrAfter lowerBound: Int) -> Int? {
            guard let candidates = places[word] else { return nil }
            var low = 0
            var high = candidates.count
            while low < high {
                let middle = (low + high) / 2
                if candidates[middle] < lowerBound { low = middle + 1 } else { high = middle }
            }
            return low < candidates.count ? candidates[low] : nil
        }

        func matchingOrigins(
            _ token: GrammarToken, allowingRomanisedHindiSpellings: Bool, excluding used: Set<Int>
        ) -> [Int]? {
            let exact = places[token.matching] ?? []
            if let match = exact.first(where: { !used.contains($0) }) { return [match] }

            // Preserve compound identifier matches, consuming each source word at most once.
            let parts = MeaningPreservationGuard.identifierParts(token.text)
            if parts.count > 1 {
                var next = 0
                var matched: [Int] = []
                for part in parts {
                    guard let place = firstOccurrence(of: part, atOrAfter: next), !used.contains(place)
                    else { matched.removeAll(); break }
                    matched.append(place)
                    next = place + 1
                }
                if !matched.isEmpty { return matched }
            }

            if let letters = spokenLetters(spelling: token.matching, excluding: used) { return letters }

            return tokens.indices.first { index in
                !used.contains(index)
                    && WordForms.sameForm(
                        tokens[index].matching, token.matching, allowingRegularInflections: false,
                        allowingRomanisedHindiSpellings: allowingRomanisedHindiSpellings)
            }.map { [$0] }
        }

        /// Finds the adjacent unused letter names spoken one per word that spell the written initialism letter for letter.
        private func spokenLetters(spelling initialism: String, excluding used: Set<Int>) -> [Int]? {
            let letters = initialism.map(String.init)
            guard letters.count > 1, initialism.allSatisfy(\.isLetter), tokens.count >= letters.count else {
                return nil
            }
            for start in 0...(tokens.count - letters.count) {
                let run = Array(start..<(start + letters.count))
                if zip(run, letters).allSatisfy({ !used.contains($0) && tokens[$0].matching == $1 }) {
                    return run
                }
            }
            return nil
        }

        func contains(_ word: String) -> Bool { places[word] != nil }

        func spells(_ identifier: String) -> Bool {
            let parts = MeaningPreservationGuard.identifierParts(identifier)
            guard parts.count > 1 else { return false }
            var next = 0
            for part in parts {
                guard let place = firstOccurrence(of: part, atOrAfter: next) else { return false }
                next = place + 1
            }
            return true
        }
    }

    /// Number spellings grouped by their numeral so occurrence indexes can add reverse matches in one lookup.
    private static let numberWordsByNumeral: [String: Set<String>] = numberWords.reduce(into: [:]) {
        index, entry in
        index[entry.value, default: []].insert(entry.key)
    }

    /// Whether a rewritten word preserves the kept word as a listed form, numeral, homophone, identifier spelling, or contracted auxiliary.
    static func survives(
        _ word: String, as candidate: GrammarToken, allowingRomanisedHindiSpellings: Bool = false
    ) -> Bool {
        if WordForms.sameForm(
            word, candidate.matching, allowingRegularInflections: false,
            allowingRomanisedHindiSpellings: allowingRomanisedHindiSpellings)
        {
            return true
        }
        if numberWords[word] == candidate.matching { return true }
        if numberWords[candidate.matching] == word { return true }
        // A misheard sound-alike respelled is the same spoken word, and only the hand-kept table says which are.
        if Homophones.share(word, candidate.matching) { return true }
        // A word spelled into an identifier — "invoices" inside "fetchInvoices" — is still there.
        if symbolNames[word] == nil, WordForms.spelledInto(word, candidate.text) { return true }
        // An auxiliary the rewrite contracted to its "n't" form is the same word.
        if Self.auxContractionRoots.contains(word), candidate.matching == "\(word)nt" { return true }
        if Self.auxContractionRoots.contains(candidate.matching), word == "\(candidate.matching)nt" {
            return true
        }
        return false
    }

    /// Spells each `H:MM` back as the kept `H.MM` that `NumberFormsPass` would itself write as that clock.
    static func respellingClockTimes(_ rewritten: String, as kept: String) -> String {
        let clocks = NumberFormsPass.dottedClockTimes(in: kept)
        guard !clocks.isEmpty else { return rewritten }
        var result = rewritten
        for dotted in clocks {
            let colon = dotted.replacingOccurrences(of: ".", with: ":")
            result = result.replacingOccurrences(
                of: "(?<![\\d.:])\(colon)(?![\\d:]|\\.\\d)", with: dotted, options: .regularExpression)
        }
        return result
    }

    /// Aux verbs the rewrite can still contract to the same word; a dropped or substituted one is a rewrite.
    static let auxContractionRoots: Set<String> = [
        "do", "does", "did",
        "is", "are", "was", "were",
        "have", "has", "had",
        "will", "would", "shall", "should",
        "can", "could", "may", "might", "must",
    ]

    /// Detects romanised Hindi from a negation or a known verb form outside the ambiguous spelling pairs.
    private static func hasRomanisedHindiContext(_ tokens: [GrammarToken]) -> Bool {
        tokens.contains { token in
            let word = token.matching
            return isNegation(word) || WordForms.hindiVerbStems.contains(word)
                || WordForms.hindiVerbStems.contains { WordForms.hindiForms(of: $0).contains(word) }
        }
    }

    /// How many words in `tokens` turn a sentence's meaning around.
    static func negators(in tokens: [GrammarToken]) -> Int {
        tokens.filter { isNegation($0.matching) }.count
    }

    /// Whether a word reverses a sentence, read without its apostrophes so "doesn't" and "doesnt" are one negation.
    static func isNegation(_ word: String) -> Bool {
        negatingWords.contains(word.replacingOccurrences(of: "'", with: ""))
    }

    /// The words that reverse a sentence, apostrophes aside; dropping or adding one is the worst edit the model can make.
    static let negatingWords: Set<String> =
        englishNegations.union(hindiNegations)

    /// English, with the apostrophes already out, which is the form `matching` carries.
    static let englishNegations: Set<String> = [
        "not", "no", "never", "none", "nothing", "nobody", "nowhere", "neither", "nor", "cannot",
        "dont", "doesnt", "didnt", "wont", "wouldnt", "cant", "couldnt", "shouldnt", "isnt",
        "arent", "wasnt", "werent", "hasnt", "havent", "hadnt", "mustnt", "aint", "neednt",
    ]

    /// Hindi in both scripts, since the prompt asks the model to romanise and the negation must survive that.
    static let hindiNegations: Set<String> = [
        "\u{0928}\u{0939}\u{0940}\u{0902}", "\u{0928}\u{093E}", "\u{092E}\u{0924}",
        "nahi", "nahin", "nahee", "na", "mat",
    ]

    /// Function words added plus removed, counted as multisets over the supplied runs.
    static func functionWordChurn(_ kept: [GrammarToken], _ rewritten: [GrammarToken]) -> Int {
        func counts(_ tokens: [GrammarToken]) -> [String: Int] {
            var result: [String: Int] = [:]
            for token in tokens where token.isPlain && !isContent(token) {
                result[token.lookup, default: 0] += 1
            }
            return result
        }
        let before = counts(kept)
        let after = counts(rewritten)
        return Set(before.keys).union(after.keys).reduce(0) { $0 + abs((before[$1] ?? 0) - (after[$1] ?? 0)) }
    }

    /// Sentences in the rewrite, counted by closing marks followed by space or end, never below one.
    static func sentenceCount(_ text: String) -> Int {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let count = words.indices.count { index in
            FirstWordPass.endsSentence(words[index], followedBy: words.dropFirst(index + 1).first)
        }
        return max(1, count)
    }

    // MARK: Checks

    /// The first number the rewrite states that the speaker did not state, there and that many times, or nil.
    static func inventedNumber(original: String, rewritten: String) -> String? {
        // Read in words on the written side too, so "twenty chairs" is refused where "20 chairs" already was.
        var spoken = numberSequence(in: original, reading: numberWords)[...]
        for number in numberSequence(in: rewritten, reading: englishNumberWords) {
            guard let found = spoken.firstIndex(of: number) else { return number }
            spoken = spoken[(found + 1)...]
        }
        return nil
    }

    /// A number whose sign or symbol the rewrite dropped, changed or invented; the digits alone are `inventedNumber`'s job.
    static func changedQuantity(original: String, rewritten: String) -> String? {
        let spoken = Quantities.read(in: original)
        let written = Quantities.read(in: rewritten)
        guard !spoken.isEmpty, !written.isEmpty else { return nil }
        for (quantity, found) in zip(spoken, written) {
            if quantity.digits != found.digits || quantity.sign != found.sign
                || quantity.symbol != found.symbol
            {
                return quantity.written
            }
        }
        return written.count < spoken.count ? spoken[written.count].written : nil
    }

    /// Refuses a rewrite that changes an amount already written with Indian digit grouping.
    static func changedIndianGrouping(original: String, rewritten: String) -> String? {
        let spoken = numericSpellings(in: original)
        let written = numericSpellings(in: rewritten)
        for (index, spelling) in spoken.enumerated() where isIndianGrouped(spelling) {
            guard written.indices.contains(index), written[index] == spelling else { return spelling }
        }
        return nil
    }

    /// The digit runs and comma separators as they appear, kept in text order.
    private static func numericSpellings(in text: String) -> [String] {
        let characters = Array(text)
        var spellings: [String] = []
        var index = 0
        while index < characters.count {
            guard characters[index].isNumber else {
                index += 1
                continue
            }
            let start = index
            index += 1
            while index < characters.count {
                if characters[index].isNumber {
                    index += 1
                } else if characters[index] == ",", index + 1 < characters.count,
                    characters[index + 1].isNumber
                {
                    index += 1
                } else {
                    break
                }
            }
            spellings.append(String(characters[start..<index]))
        }
        return spellings
    }

    /// Indian grouping has a one or two digit leading group, two digit middle groups, and a three digit final group.
    private static func isIndianGrouped(_ spelling: String) -> Bool {
        let groups = spelling.split(separator: ",")
        guard groups.count >= 3, (1...2).contains(groups[0].count), groups.last?.count == 3 else {
            return false
        }
        return groups.dropFirst().dropLast().allSatisfy { $0.count == 2 }
    }

    /// The numbers a text states, in order and with repeats kept, each number word read through `table` and every run of them composed after it.
    static func numberSequence(in text: String, reading table: [String: String]) -> [String] {
        var pieces: [(text: String, isDigits: Bool)] = []
        var run = ""
        var runIsDigits = false
        func flush() {
            if !run.isEmpty { pieces.append((run, runIsDigits)) }
            run = ""
        }
        for character in withoutThousandsSeparators(text) {
            guard character.isNumber || character.isLetter else {
                flush()
                continue
            }
            if character.isNumber != runIsDigits { flush() }
            runIsDigits = character.isNumber
            run.append(character)
        }
        flush()
        // A run of digits stands between number words, so it ends a spoken number rather than joining it.
        let words = pieces.map { $0.isDigits ? "" : $0.text.lowercased() }
        var found: [String] = []
        var index = words.startIndex
        while index < words.endIndex {
            if pieces[index].isDigits {
                found.append(pieces[index].text)
                index += 1
            } else if let read = NumberWords.cardinal(words[index...]), read.count > 1 {
                found += words[index..<(index + read.count)].compactMap { table[$0] }
                found.append(String(read.value))
                index += read.count
            } else {
                if let digits = table[words[index]] { found.append(digits) }
                index += 1
            }
        }
        return found
    }

    /// Drops a comma that groups digits, so "12,000" and "1,50,000" read as the numbers they are.
    static func withoutThousandsSeparators(_ text: String) -> String {
        let characters = Array(text)
        var result = ""
        for (index, character) in characters.enumerated() {
            if character == ",", index > 0, characters[index - 1].isNumber {
                let run = characters[(index + 1)...].prefix(while: \.isNumber).count
                if run == 2 || run == 3 { continue }
            }
            result.append(character)
        }
        return result
    }

    /// Digits people dictate as words, in English and Hindi; traps on first use if the tables share a word.
    static let numberWords: [String: String] = Dictionary(
        uniqueKeysWithValues: Array(englishNumberWords) + NumberWords.hindi.map { ($0.key, String($0.value)) }
    )

    /// The English number words as digits, read from `NumberWords`.
    private static let englishNumberWords: [String: String] = NumberWords.english.mapValues(String.init)

    /// The positions of every spoken number run the rewrite wrote as the one numeral it comes to.
    static func composedNumbers(_ tokens: [GrammarToken], in pool: Set<String>) -> Set<Int> {
        var covered: Set<Int> = []
        for run in cardinalRuns(tokens.map(\.matching)) where pool.contains(String(run.value)) {
            covered.formUnion(run.start..<(run.start + run.count))
        }
        return covered
    }

    /// Every run of two or more words that `NumberWords` reads as one cardinal, longest first from each start.
    private static func cardinalRuns(_ words: [String]) -> [(start: Int, count: Int, value: Int)] {
        var runs: [(start: Int, count: Int, value: Int)] = []
        var index = words.startIndex
        while index < words.endIndex {
            guard let read = NumberWords.cardinal(words[index...]), read.count > 1 else {
                index += 1
                continue
            }
            runs.append((index, read.count, read.value))
            index += read.count
        }
        return runs
    }
}
