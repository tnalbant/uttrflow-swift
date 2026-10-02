/// Where the discarded half of a spoken correction begins, once a trigger phrase announces one. See `Docs/cleanup.md`.
public enum Restatement {
    /// Phrases that announce a correction, longest first so "no sorry" is one trigger rather than two.
    public static let triggers: [[String]] = [
        ["no", "sorry"], ["no", "wait"], ["wait", "sorry"], ["scratch", "that"], ["never", "mind"],
        ["i", "mean"], ["nahi", "nahi"], ["mera", "matlab"],
        ["no"], ["sorry"], ["actually"],
    ]

    /// How many words back the discarded half may reach.
    public static let reach = 6

    private static let hindiNumberWords: Set<String> = [
        "ek", "do", "teen", "char", "chaar", "paanch", "panch", "chhe", "chhah", "che", "saat",
        "aath", "nau", "das", "gyarah", "baarah", "barah", "terah", "chaudah", "pandrah",
        "solah", "satrah", "atharah", "unnis", "bees",
    ]

    private static let copulas: Set<String> = ["am", "is", "are", "was", "were", "be", "being", "been"]

    /// Words that head an answer, which a second answer pairs with rather than takes back.
    public static let answerHeads: Set<String> = [
        "yes", "yeah", "yep", "no", "nope", "sorry", "thanks", "thank", "okay", "ok",
    ]

    /// Words a restated phrase may not anchor on, because a fresh clause starts with them far more often.
    public static let weakAnchors = Set(subjects + ["yes", "yeah", "ok", "okay", "oh", "well"])
        .union(contractedSubjects).union(hindiSubjects)

    /// English subject words, each of which heads a fresh clause.
    static let subjects = ["i", "we", "you", "he", "she", "they", "it", "that", "this", "there"]

    /// Every contracted form of a subject word ("he's", "we're", "they'll"), in either apostrophe.
    static let contractedSubjects = Set(
        subjects.flatMap { subject in
            ["s", "m", "re", "ll", "ve", "d"].flatMap { ending in
                ["'", "\u{2019}"].map { subject + $0 + ending }
            }
        })

    /// Hindi pronouns and subject words, romanised and in Devanagari, which start a fresh clause as English ones do.
    static let hindiSubjects: Set<String> = [
        "main", "mai", "maine", "mujhe", "hum", "humne", "tum", "aap", "wo", "woh", "ye", "yeh",
        "mera", "meri", "mere", "मैं", "मैंने", "मुझे", "हम", "तुम", "आप", "वो", "वह", "ये", "यह",
        "मेरा", "मेरी", "मेरे",
    ]

    /// How many words at `position` are trigger phrases run together, such as "no wait".
    public static func triggerRun(at position: Int, in live: [Int], of draft: Draft) -> Int {
        var length = 0
        while let next = triggerLength(at: position + length, in: live, of: draft) { length += next }
        return length
    }

    private static func triggerLength(at position: Int, in live: [Int], of draft: Draft) -> Int? {
        for trigger in triggers where position + trigger.count <= live.count {
            let keys = live[position..<position + trigger.count].map { draft.shape(at: $0).key }
            if keys == trigger { return trigger.count }
        }
        return nil
    }

    /// Where the discarded half starts, or nil when the halves do not match in shape.
    public static func discardedStart(
        before trigger: Int, after restart: Int, in live: [Int], of draft: Draft
    ) -> Int? {
        let earliest = max(0, trigger - reach)
        let firstAfter = draft.shape(at: live[restart]).key
        let triggerWords = live[trigger..<restart].map { draft.shape(at: $0).key }
        let isHindiDoubleNegative = triggerWords == ["nahi", "nahi"]
        let isPausedMeraMatlab =
            triggerWords == ["mera", "matlab"]
            && draft.shape(at: live[restart - 1]).suffix.contains(",")
        if isHindiDoubleNegative || isPausedMeraMatlab {
            return hindiNumberStart(before: trigger, after: restart, in: live, of: draft)
        }
        if triggerWords == ["mera", "matlab"] { return nil }
        guard !isReportedAnswer(triggerWords, before: trigger, in: live, of: draft) else { return nil }
        let through = standsAlone(trigger, before: restart, in: live, of: draft)
        if NumberWords.isNumber(firstAfter),
            let end = numberEnd(before: trigger, after: restart, in: live, of: draft)
        {
            guard through || !endsSentence(trigger - 1, in: live, of: draft) else { return nil }
            var start = end
            while start > earliest, NumberWords.isNumber(draft.shape(at: live[start - 1]).key),
                !endsSentence(start - 1, in: live, of: draft)
            {
                start -= 1
            }
            guard !coordinates(start, before: trigger, in: live, of: draft) else { return nil }
            return start
        }
        guard !weakAnchors.contains(firstAfter) else { return nil }
        let replacesOneWord = replacesSingleWord(
            before: trigger, after: restart, triggerWords: triggerWords, in: live, of: draft)
        for candidate in stride(from: trigger - 1, through: earliest, by: -1) {
            if anchors(draft.shape(at: live[candidate]).key, the: firstAfter) {
                guard holdsContent(candidate..<trigger, in: live, of: draft),
                    !coordinates(candidate, before: trigger, in: live, of: draft)
                else { return nil }
                return candidate
            }
            if endsSentence(candidate, in: live, of: draft), !(through && candidate == trigger - 1) {
                return replacesOneWord ? trigger - 1 : nil
            }
        }
        return replacesOneWord ? trigger - 1 : nil
    }

    /// A bare no after a copula and before a comma completes a reported answer clause.
    private static func isReportedAnswer(
        _ trigger: [String], before position: Int, in live: [Int], of draft: Draft
    ) -> Bool {
        guard trigger == ["no"], position > 0,
            copulas.contains(draft.shape(at: live[position - 1]).key),
            draft.shape(at: live[position]).suffix.contains(",")
        else { return false }
        return true
    }

    /// Hindi triggers take back a number only when the following phrase repeats, so ordinary speech stays intact.
    private static func hindiNumberStart(
        before trigger: Int, after restart: Int, in live: [Int], of draft: Draft
    ) -> Int? {
        guard restart < live.count else { return nil }
        let replacement = draft.shape(at: live[restart]).key
        guard isHindiOrDigitNumber(replacement) else { return nil }

        let earliest = max(0, trigger - reach)
        if trigger > earliest {
            for start in stride(from: trigger - 1, through: earliest, by: -1)
            where isHindiOrDigitNumber(draft.shape(at: live[start]).key) {
                let oldTail = live[(start + 1)..<trigger].map { draft.shape(at: $0).key }
                let newTailStart = restart + 1
                let newTailEnd = newTailStart + oldTail.count
                guard !oldTail.isEmpty, newTailEnd <= live.count else { continue }
                let newTail = live[newTailStart..<newTailEnd].map { draft.shape(at: $0).key }
                guard oldTail == newTail,
                    !(start..<trigger).contains(where: { endsSentence($0, in: live, of: draft) }),
                    !(restart..<newTailEnd).contains(where: { endsSentence($0, in: live, of: draft) })
                else { continue }
                return start
            }
        }

        guard trigger > 0 else { return nil }
        let oldNumber = draft.shape(at: live[trigger - 1]).key
        return isHindiOrDigitNumber(oldNumber) ? trigger - 1 : nil
    }

    /// Whether a word is a supported romanised Hindi, English or digit number.
    private static func isHindiOrDigitNumber(_ key: String) -> Bool {
        hindiNumberWords.contains(key) || NumberWords.isNumber(key)
    }

    /// Whether a trigger sits between two content words in one sentence, replacing the word directly before it.
    private static func replacesSingleWord(
        before trigger: Int, after restart: Int, triggerWords: [String], in live: [Int], of draft: Draft
    ) -> Bool {
        guard trigger > 0, restart < live.count,
            !endsSentence(trigger - 1, in: live, of: draft),
            FunctionWords.isContent(draft.shape(at: live[trigger - 1]).key),
            FunctionWords.isContent(draft.shape(at: live[restart]).key),
            !coordinates(trigger - 1, before: trigger, in: live, of: draft)
        else { return false }

        // Ordinary "actually" and "no" join content words too, so their pause must corroborate the correction.
        if triggerWords == ["actually"] || triggerWords == ["no"] {
            return draft.shape(at: live[trigger - 1]).suffix.contains(",")
        }
        return true
    }

    /// A camel-case dictionary word can retain the first heard word as a component, such as `payment` in `PaymentSheet`.
    private static func anchors(_ heard: String, the written: String) -> Bool {
        guard heard != written, heard.count >= 3 else { return heard == written }
        let characters = Array(written)
        var start = characters.startIndex
        for index in characters.indices where index > start && characters[index].isUppercase {
            if String(characters[start..<index]).lowercased() == heard { return true }
            start = index
        }
        return String(characters[start...]).lowercased() == heard
    }

    /// Whether the trigger is a sentence of its own after a full stop ("Tuesday. Scratch that. Wednesday"), which is a pause rather than two sentences.
    public static func standsAlone(
        _ trigger: Int, before restart: Int, in live: [Int], of draft: Draft
    ) -> Bool {
        guard trigger > 0, restart > trigger, restart <= live.count else { return false }
        let phrase = (trigger..<restart).map { draft.shape(at: live[$0]) }
        // A bare "No." is an answer far more often than a correction.
        guard phrase.map(\.key) != ["no"] else { return false }
        return closesWithAStop(trigger - 1, in: live, of: draft)
            && closesWithAStop(restart - 1, in: live, of: draft)
            && phrase.allSatisfy { !$0.suffix.contains(where: { "?!".contains($0) }) }
    }

    /// Whether the word ends its sentence with a full stop, rather than a question or an exclamation.
    private static func closesWithAStop(_ position: Int, in live: [Int], of draft: Draft) -> Bool {
        let suffix = draft.shape(at: live[position]).suffix
        return suffix.contains(".") && !suffix.contains(where: { "?!".contains($0) })
    }

    /// The last word of the number taken back, stepping over a unit the restatement repeats ("twelve boxes i mean fifteen boxes").
    private static func numberEnd(
        before trigger: Int, after restart: Int, in live: [Int], of draft: Draft
    ) -> Int? {
        let unit = trigger - 1
        let unitKey = draft.shape(at: live[unit]).key
        if NumberWords.isNumber(unitKey) { return unit }
        guard unit > 0, NumberWords.isNumber(draft.shape(at: live[unit - 1]).key),
            !endsSentence(unit - 1, in: live, of: draft)
        else { return nil }
        var next = restart
        while next < live.count, NumberWords.isNumber(draft.shape(at: live[next]).key) {
            // A unit past a stop belongs to the next sentence, not to this restatement.
            guard !endsSentence(next, in: live, of: draft) else { return nil }
            next += 1
        }
        guard next < live.count, draft.shape(at: live[next]).key == unitKey else { return nil }
        return unit - 1
    }

    /// Whether the word at `position` closes a sentence, which no anchor may reach past to take words out of the sentence before.
    private static func endsSentence(_ position: Int, in live: [Int], of draft: Draft) -> Bool {
        draft.shape(at: live[position]).endsSentence
    }

    /// Whether the words the correction would take back hold anything the speaker meant.
    private static func holdsContent(_ span: Range<Int>, in live: [Int], of draft: Draft) -> Bool {
        span.contains { FunctionWords.isContent(draft.shape(at: live[$0]).key) }
    }

    /// Whether the trigger heads each item of a list rather than correcting one: the word before the half it would take back is the trigger over again, or an answer this trigger answers ("yes … no …", "thanks … sorry …").
    private static func coordinates(
        _ start: Int, before trigger: Int, in live: [Int], of draft: Draft
    ) -> Bool {
        guard start > 0 else { return false }
        let before = draft.shape(at: live[start - 1]).key
        let head = draft.shape(at: live[trigger]).key
        return before == head || (answerHeads.contains(before) && answerHeads.contains(head))
    }
}
