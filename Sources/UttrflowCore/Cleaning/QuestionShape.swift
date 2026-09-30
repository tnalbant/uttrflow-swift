/// Whether a sentence asks a direct question by its word order alone, read the same way on every path. See `Docs/cleanup.md`.
public enum QuestionShape {
    /// Whether the words of one sentence ask a direct question.
    public static func asks(_ sentence: [WordShape]) -> Bool {
        let shapes = sentence.filter { !$0.key.isEmpty }
        let words = shapes.map { $0.key.replacingOccurrences(of: "\u{2019}", with: "'") }
        guard !words.isEmpty else { return false }
        if endsOnATag(words) || trailingRightTagStart(in: shapes) != nil { return true }
        // The last clause is where "I sent it, did you see it" asks.
        let openingClause = Array(words.drop(while: openers.contains))
        if opensAQuestion(openingClause) { return true }
        guard let start = trailingQuestionStart(in: shapes) else { return false }
        let clause = Array(words[start...].drop(while: openers.contains))
        return opensAQuestion(clause) && !runsOn(clause)
    }

    /// The start of a trailing question after a comma or an inverted request modal.
    static func trailingQuestionStart(in shapes: [WordShape]) -> Int? {
        if let comma = shapes.dropLast().lastIndex(where: { $0.suffix.contains(",") }) {
            return comma + 1
        }
        return trailingRequestStart(in: shapes)
    }

    /// The final "right" when a subject and predicate make the words before it a clause.
    public static func trailingRightTagStart(in shapes: [WordShape]) -> Int? {
        let spoken = shapes.indices.filter { !shapes[$0].key.isEmpty }
        let words = spoken.map { shapes[$0].key.replacingOccurrences(of: "\u{2019}", with: "'") }
        guard words.last == "right", hasClauseBeforeRight(Array(words.dropLast())) else { return nil }
        return spoken.last
    }

    /// Whether a clause-starting subject has a predicate and a plausible complement before "right".
    private static func hasClauseBeforeRight(_ words: [String]) -> Bool {
        let clause = Array(words.drop(while: openers.contains))
        guard let subjectEnd = rightTagSubjectEnd(in: clause) else { return false }
        let predicateIndex = subjectEnd + 1
        guard clause.indices.contains(predicateIndex), rightTagPredicates.contains(clause[predicateIndex])
        else {
            return false
        }
        let predicate = clause[predicateIndex]
        let complement = Array(clause.dropFirst(predicateIndex + 1))
        guard !rightComplementVerbs.contains(predicate), !complement.isEmpty,
            !directionalRightVerbs.contains(complement.last ?? "")
        else { return false }
        if copulaVerbs.contains(predicate) {
            return complement.count >= 2 || copulaRightComplements.contains(complement.last ?? "")
        }
        return complement.count >= 2
    }

    /// The subject at a clause's opening: a pronoun or a determiner with its noun.
    private static func rightTagSubjectEnd(in clause: [String]) -> Int? {
        guard let first = clause.first else { return nil }
        if subjects.contains(first) { return 0 }
        return determiners.contains(first) && clause.count >= 2 ? 1 : nil
    }

    /// The start of a trailing inverted request without a spoken comma.
    public static func trailingRequestStart(in shapes: [WordShape]) -> Int? {
        let words = shapes.map(\.key)
        return words.indices.dropFirst().first { index in
            guard index + 1 < words.count, requestModals.contains(words[index]),
                requestSubjects.contains(words[index + 1])
            else { return false }
            let clause = Array(words[index...].drop(while: openers.contains))
            return opensAQuestion(clause) && !runsOn(clause)
        }
    }

    /// Whether a clause opens the way a question does: a question word before its verb, or a verb before its subject.
    private static func opensAQuestion(_ clause: [String]) -> Bool {
        guard let first = clause.first else { return false }
        let second = clause.dropFirst().first ?? ""
        if contractedQuestionWords.contains(first) { return true }
        if questionWords.contains(first) {
            // "what we need is…" names a thing; "what time is it" asks, so a subject before the verb says no.
            for word in clause.dropFirst().prefix(3) {
                if subjects.contains(word) { return false }
                if verbsBeforeSubject.contains(word) || pronounVerbs.contains(word) {
                    return true
                }
                if lexicalQuestionVerbs.contains(word) {
                    let following = clause.dropFirst().drop(while: { $0 != word }).dropFirst().first
                    return following.map { !subjects.contains($0) && !determiners.contains($0) } ?? true
                }
            }
            return false
        }
        if verbsBeforeSubject.contains(first) {
            return subjects.contains(second) || determiners.contains(second)
        }
        // "Do the dishes" and "have a seat" tell rather than ask, so these ask only before a pronoun.
        if pronounVerbs.contains(first) { return subjects.contains(second) }
        return hindiQuestionWords.contains(first) || (first == "kya" && hindiSubjects.contains(second))
    }

    /// Whether a new subject starts later in the clause, as in "are you around yet I should be there", where the mark's place is unknown.
    private static func runsOn(_ clause: [String]) -> Bool {
        // The subject straight after the question's verb is the one it inverted, so the search starts past it.
        let verb =
            clause.prefix(4).firstIndex { verbsBeforeSubject.contains($0) || pronounVerbs.contains($0) } ?? 1
        return clause.dropFirst(verb + 2).contains {
            newSubjects.contains($0) || contractedNewSubjects.contains($0)
        }
    }

    /// Whether the sentence closes on a question tag: "isn't it", "don't you", or Hindi "… hai kya".
    private static func endsOnATag(_ words: [String]) -> Bool {
        guard words.count >= 3, let last = words.last else { return false }
        let before = words[words.count - 2]
        if subjects.contains(last), negativeVerbs.contains(before) { return true }
        return last == "kya" && hindiVerbs.contains(before)
    }

    /// Words a question may start after: "so did you…", "okay, can we…".
    static let openers: Set<String> = [
        "so", "and", "but", "okay", "ok", "oh", "well", "also", "then", "hey", "now", "anyway",
    ]

    /// English question words.
    static let questionWords: Set<String> = [
        "what", "where", "when", "why", "who", "whom", "whose", "which", "how",
    ]

    /// A question word contracted onto "is", which asks whatever follows.
    static let contractedQuestionWords: Set<String> = [
        "what's", "where's", "who's", "how's", "when's", "why's",
    ]

    /// Verbs that ask by standing before a subject or a determiner: "is the build green", "can we meet".
    static let verbsBeforeSubject: Set<String> = [
        "is", "are", "was", "were", "am", "does", "did", "has", "had", "can", "could", "will", "would",
        "should",
        "shall", "may", "might", "isn't", "aren't", "wasn't", "weren't", "doesn't", "didn't", "hasn't",
        "hadn't",
        "can't", "couldn't", "won't", "wouldn't", "shouldn't",
    ]

    /// Modals that commonly start a request after a spoken statement.
    private static let requestModals: Set<String> = ["can", "could"]

    /// Subjects used by short trailing requests.
    private static let requestSubjects: Set<String> = ["you", "we", "someone"]

    /// Verbs that also start a command, so they ask only before a pronoun: "do you", not "do the dishes".
    static let pronounVerbs: Set<String> = ["do", "have", "don't", "haven't"]

    /// Common present and past lexical verbs that can follow a question word directly.
    private static let lexicalQuestionVerbs: Set<String> = [
        "happens", "happen", "happened", "changed", "change", "changes", "works", "work", "worked",
        "fails", "fail", "failed", "comes", "come", "came", "goes", "go", "went", "looks", "look",
        "looked", "means", "mean", "meant", "costs", "cost", "costed", "matters", "matter", "mattered",
        "causes", "cause", "caused", "starts", "start", "started", "ends", "end", "ended", "breaks",
        "break", "broke", "broken", "shows", "show", "showed", "shown", "runs", "run", "ran", "says",
        "say", "said", "takes", "take", "took", "taken", "makes", "make", "made", "gets", "get", "got",
        "gives", "give", "gave", "given", "finds", "find", "found", "keeps", "keep", "kept", "leaves",
        "leave", "left", "happening",
    ]

    /// Predicates used to distinguish a closing tag from "turn right" or "that's right".
    private static let rightTagPredicates =
        verbsBeforeSubject.union(pronounVerbs).union(lexicalQuestionVerbs).union(["sent", "saved"])

    /// Copulas need a complement beyond the verb, as in "the meeting is at three".
    private static let copulaVerbs: Set<String> = ["is", "are", "was", "were", "am", "be", "been", "being"]

    /// Predicates whose complement is "right" rather than a closing tag.
    private static let rightComplementVerbs: Set<String> = ["get", "gets", "got", "getting"]

    /// One-word complements that complete a copula before a right tag.
    private static let copulaRightComplements: Set<String> = ["saved"]

    /// Directional complements that end in "right" without a tag.
    private static let directionalRightVerbs: Set<String> = [
        "turn", "go", "move", "keep", "head", "bear", "drive",
    ]

    /// Negative verbs, which with a pronoun after them close a sentence as a tag: "isn't it", "don't you".
    static let negativeVerbs: Set<String> = [
        "isn't", "aren't", "wasn't", "weren't", "doesn't", "didn't", "hasn't", "hadn't", "can't", "couldn't",
        "won't",
        "wouldn't", "shouldn't", "don't", "haven't",
    ]

    /// Subject pronouns and the indefinite subjects a question inverts around.
    static let subjects: Set<String> = [
        "i", "you", "we", "they", "he", "she", "it", "there", "anyone", "anybody", "someone", "somebody",
        "everyone",
        "everybody", "anything", "something", "everything",
    ]

    /// Pronouns that can only be a subject, so one past a question's opening starts a second clause.
    static let newSubjects: Set<String> = ["i", "we", "he", "she", "they"]

    /// Every contracted form of those pronouns: "I'm", "we'll", "they've".
    static let contractedNewSubjects = Set(
        newSubjects.flatMap { subject in ["'m", "'s", "'re", "'ll", "'ve", "'d"].map { subject + $0 } })

    /// Words that open a noun phrase a question can invert around: "is the build", "can your team".
    static let determiners: Set<String> = [
        "the", "a", "an", "my", "your", "our", "his", "her", "their", "its", "this", "that", "these", "those",
        "any",
        "some",
    ]

    /// Romanised Hindi question words that ask from the start of a sentence.
    static let hindiQuestionWords: Set<String> = [
        "kaun", "kahan", "kab", "kaise", "kyun", "kyon", "kitna", "kitne", "kitni", "kiska", "kiski", "kiske",
        "kisne", "kisko",
    ]

    /// Romanised Hindi subject pronouns, which "kya" asks about from the start of a sentence.
    static let hindiSubjects: Set<String> = [
        "tum", "aap", "tu", "wo", "woh", "ye", "yeh", "hum", "main", "mai", "unhone", "usne", "humne",
        "tumne", "aapne",
    ]

    /// Romanised Hindi verb endings a closing "kya" turns into a question: "aa rahe ho kya".
    static let hindiVerbs: Set<String> = [
        "hai", "hain", "ho", "hoon", "tha", "thi", "the", "hoga", "hogi", "honge",
    ]
}
