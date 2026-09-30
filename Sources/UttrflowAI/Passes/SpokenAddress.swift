import UttrflowCore

/// An email address said aloud — a local part, "at", and a domain — and the address its words spell. See `Docs/cleanup.md`.
struct SpokenAddress: Equatable {
    /// How many live positions the address's words span.
    let length: Int
    /// The address as it is written, carrying the marks its first and last word stood with.
    let text: String

    /// The endings that make a spoken domain a domain; an unknown one is left as words rather than guessed at.
    static let topLevels: Set<String> = [
        "com", "net", "org", "edu", "gov", "mil", "int", "info", "biz",
        "io", "co", "ai", "dev", "app", "me", "sh", "xyz", "tech", "online", "site", "store", "cloud",
        "in", "uk", "us", "ca", "au", "de", "fr", "nl", "es", "it", "jp", "cn", "br", "ru", "ie", "nz",
    ]

    /// The words that announce an address, after which a local part spelled as a plain word is a mailbox.
    static let introducers: Set<String> = [
        "email", "emails", "emailed", "mail", "mails", "mailed", "address", "addresses",
        "send", "sends", "sent", "sending", "forward", "forwards", "forwarded",
        "copy", "copies", "copied", "cc", "write", "writes", "wrote", "contact", "reach", "invite",
    ]

    /// How many content words back an announcing word may stand from a local part spelled as a plain word.
    static let introducerReach = 2

    /// One side of an address: how many live positions it spans and the labels its words spell.
    struct Part: Equatable {
        let length: Int
        let labels: [String]

        /// The labels written as one, a dot wherever a spoken or a heard one stood between them.
        var spelled: String { labels.joined(separator: ".") }

        /// Whether the words say for themselves that they are an address: more than one label, or a mark or digit inside one.
        var isShaped: Bool {
            labels.count > 1 || labels.contains { label in label.contains { !$0.isLetter } }
        }

        /// Whether the words hold a letter, which a local part has and a spoken amount does not.
        var hasLetter: Bool { labels.contains { $0.contains(where: \.isLetter) } }
    }

    /// The address spoken from `position`, or nil where the words are not one.
    static func read(at position: Int, in live: [Int], of draft: Draft) -> SpokenAddress? {
        let run = position..<draft.sentenceEnd(from: position, in: live)
        guard let local = part(from: position, within: run, in: live, of: draft),
            local.hasLetter, FunctionWords.isContent(local.spelled)
        else { return nil }
        let joint = position + local.length
        guard joint + 1 < run.upperBound, draft.shape(at: live[joint]).key == "at",
            let domain = part(from: joint + 1, within: run, in: live, of: draft),
            domain.labels.count > 1, let top = domain.labels.last, topLevels.contains(top),
            local.isShaped || isIntroduced(before: position, in: live, of: draft)
        else { return nil }
        let span = position..<(joint + 1 + domain.length)
        guard onlyEndsAreMarked(span, in: live, of: draft) else { return nil }
        let first = draft.shape(at: live[span.lowerBound])
        let last = draft.shape(at: live[span.upperBound - 1])
        return SpokenAddress(
            length: span.count, text: first.prefix + local.spelled + "@" + domain.spelled + last.suffix)
    }

    /// The labels spoken from `position`, which stands inside `run`, a spoken or a heard dot carrying on to the next.
    private static func part(
        from position: Int, within run: Range<Int>, in live: [Int], of draft: Draft
    ) -> Part? {
        var labels: [String] = []
        var place = position
        while true {
            let spelled = draft.shape(at: live[place]).core
                .split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard spelled.allSatisfy(isLabel) else { return nil }
            labels += spelled
            // A spoken "dot" carries the part on into the word after it; anything else ends the part here.
            guard place + 2 < run.upperBound, draft.shape(at: live[place + 1]).key == "dot" else {
                return Part(length: place + 1 - position, labels: labels)
            }
            place += 2
        }
    }

    /// Whether a label can stand in an address: letters, digits, hyphens and underscores, and nothing else.
    private static func isLabel(_ label: String) -> Bool {
        !label.isEmpty && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    /// Whether an address is announced before a plain local part: an announcing word, or an address already written, within reach.
    private static func isIntroduced(before position: Int, in live: [Int], of draft: Draft) -> Bool {
        // A determiner in front makes the word the noun of a phrase — "send the report at example.com" — never a mailbox.
        if position > 0,
            MentionGuard.phraseOpeners.contains(draft.shape(at: live[position - 1]).key)
        {
            return false
        }
        var content = 0
        var place = position - 1
        while place >= 0, content < introducerReach {
            let shape = draft.shape(at: live[place])
            // A noun phrase cannot begin in the sentence before, which is how the mention guard reads a lookback too.
            guard !shape.endsSentence else { return false }
            if !FunctionWords.holds(shape.key) {
                if introducers.contains(shape.key) || shape.core.contains("@") { return true }
                content += 1
            }
            place -= 1
        }
        return false
    }

    /// Whether only the address's ends carry marks, a mark inside the words meaning they are not one address.
    private static func onlyEndsAreMarked(_ span: Range<Int>, in live: [Int], of draft: Draft) -> Bool {
        span.allSatisfy { place in
            let shape = draft.shape(at: live[place])
            return (place == span.lowerBound || shape.prefix.isEmpty)
                && (place == span.upperBound - 1 || shape.suffix.isEmpty)
        }
    }
}
