/// Holds the first tokens of a pass to the word the person is in the middle of, so a line cut inside a token is continued rather than started over. See `Docs/predict-context.md`, G5.
struct TokenHealing {
    /// Every token as the bytes it writes, read once per model, so a step can be masked by comparing bytes; a byte-fallback piece is its one byte, which is how an emoji or a mark is spelt.
    struct Vocabulary: Sendable {
        /// The UTF-8 bytes each token writes, by id, with the word-start mark read as the space it stands for.
        let bytes: [[UInt8]]
        /// The tokens that end a line or the turn, which a word just finished must not be followed by at once.
        let ending: Set<Int>
        /// Whether each token, by id, starts something new rather than lengthening the word before it, read once per model beside the bytes.
        let startsNewWord: [Bool]

        init(texts: [String], ending: Set<Int>) {
            let byteLevelBPE = Self.usesByteLevelBPE(texts)
            self.init(bytes: texts.map { Self.bytes(of: $0, byteLevelBPE: byteLevelBPE) }, ending: ending)
        }

        init(bytes: [[UInt8]], ending: Set<Int>) {
            self.bytes = bytes
            self.ending = ending
            startsNewWord = bytes.map(Self.startsNewWord)
        }

        /// What a piece writes: the word-start mark as a space, and a byte-fallback piece such as `<0x0A>` as the one byte it names.
        static func bytes(of piece: String, byteLevelBPE: Bool = false) -> [UInt8] {
            if piece.count == 6, piece.hasPrefix("<0x"), piece.hasSuffix(">"),
                let byte = UInt8(piece.dropFirst(3).dropLast(), radix: 16)
            {
                return [byte]
            }
            let scalars = Array(piece.unicodeScalars)
            if byteLevelBPE || scalars.contains(where: ByteLevelBPE.isEscapedScalar) {
                let bytes = scalars.compactMap(ByteLevelBPE.byte(for:))
                if bytes.count == scalars.count { return bytes }
            }
            return Array(piece.replacingOccurrences(of: "\u{2581}", with: " ").utf8)
        }

        /// Whether any piece identifies the tokenizer's vocabulary as GPT-2 byte-level BPE.
        static func usesByteLevelBPE(_ pieces: [String]) -> Bool {
            pieces.contains { $0.unicodeScalars.contains(where: ByteLevelBPE.isEscapedScalar) }
        }

        /// Reverses the byte alphabet used by GPT-2 byte-level BPE vocabularies.
        private enum ByteLevelBPE {
            private static let escapedBytes: [UInt8] =
                Array(0...32).map { UInt8($0) }
                + [127] + Array(128...160).map { UInt8($0) } + [173]

            static func isEscapedScalar(_ scalar: Unicode.Scalar) -> Bool {
                (256..<(256 + escapedBytes.count)).contains(Int(scalar.value))
            }

            static func byte(for scalar: Unicode.Scalar) -> UInt8? {
                let value = Int(scalar.value)
                if value >= 256, value < 256 + escapedBytes.count {
                    return escapedBytes[value - 256]
                }
                if (33...126).contains(value) || (161...172).contains(value) || (174...255).contains(value) {
                    return UInt8(value)
                }
                return nil
            }
        }

        /// The tokens a step may produce: those that keep to what is owed, or when nothing is owed any that adds a visible character without ending the line; a word the person finished is never overshot, and what follows it begins with a space.
        func allowed(owing owed: [UInt8], wordComplete: Bool) -> [Bool] {
            bytes.indices.map { id in
                let written = bytes[id]
                guard !written.isEmpty else { return false }
                if owed.isEmpty {
                    return !ending.contains(id) && written.contains { !Self.isSpace($0) }
                        && (!wordComplete || Self.isSpace(written[0]))
                }
                return owed.starts(with: written) || (!wordComplete && written.starts(with: owed))
            }
        }

        /// Whether a byte is a space or a tab, the whitespace a line can hold.
        static func isSpace(_ byte: UInt8) -> Bool { byte == 0x20 || byte == 0x09 }

        /// Whether a token starts something new rather than lengthening the word before it, which anything but a letter or digit at its front does.
        static func startsNewWord(_ written: [UInt8]) -> Bool {
            guard let first = String(decoding: written.prefix(4), as: UTF8.self).first else { return false }
            return !first.isLetter && !first.isNumber
        }
    }

    /// What a token starting a new word costs in logits at the step after a word the person stopped inside, so the word is lengthened unless the model is this much surer of a break. See `Docs/predict-context.md`, G6.
    static let newWordPenalty: Float = 3

    let vocabulary: Vocabulary
    /// Whether the person finished the word with a space, so it is written exactly and what follows begins with one.
    let wordComplete: Bool
    /// Whether the line may end with the word, which a word closing a sentence or a statement does.
    let mayEnd: Bool
    /// What the model must still write before it is free: the rest of the typed word, then one visible character more.
    private(set) var owed: [UInt8]
    /// Whether the word is complete and continued, after which every token is the model's own.
    private(set) var isFree = false
    /// Whether the person stopped inside a word, so a token starting a new word after it would split what they are typing.
    let isMidWord: Bool

    init(vocabulary: Vocabulary, owed: String, wordComplete: Bool, mayEnd: Bool = false) {
        self.vocabulary = vocabulary
        self.owed = Array(owed.utf8)
        self.wordComplete = wordComplete
        self.mayEnd = mayEnd
        isMidWord = !wordComplete && (owed.last.map { $0.isLetter || $0.isNumber } ?? false)
    }

    /// What a step adds to the logits: nothing for an allowed token, minus infinity for the rest, and the new-word penalty where a break would split the typed word; nothing at all once the model is free or when no token could keep to the word.
    func mask(width: Int) -> [Float]? {
        guard !isFree else { return nil }
        let allowed = vocabulary.allowed(owing: owed, wordComplete: wordComplete)
        // With no token able to keep to the word, the model is left free rather than made to choose among nothing.
        guard allowed.contains(true) else { return nil }
        // The typed word is written out, so this one step is where the model either lengthens it or breaks it.
        let maySplit = isMidWord && owed.isEmpty
        // The model's head may be wider than the vocabulary; the padding beyond it is never a token to pick.
        var mask = [Float](repeating: -.infinity, count: width)
        for (id, isAllowed) in allowed.enumerated() where isAllowed && id < width {
            mask[id] = maySplit && vocabulary.startsNewWord[id] ? -Self.newWordPenalty : 0
        }
        return mask
    }

    /// Advances what is owed by one token's text, kept apart from the model so a test can drive it.
    mutating func took(_ text: String) { took(Array(text.utf8)) }

    /// Advances what is owed by the bytes one token wrote.
    mutating func took(_ written: [UInt8]) {
        guard !owed.isEmpty else {
            // Only a visible character continues the line; a lone space would let the next token end it.
            isFree = written.contains { !Vocabulary.isSpace($0) }
            return
        }
        if written.count > owed.count, written.starts(with: owed) {
            owed = []
            isFree = true
        } else if owed.starts(with: written) {
            owed.removeFirst(written.count)
            // A word that closes the line owes nothing more once written, so the model may stop there.
            if owed.isEmpty, mayEnd { isFree = true }
        } else {
            // A token the mask should have refused: the word cannot be held any longer, so the model is left free.
            owed = []
            isFree = true
        }
    }
}

/// Holds a pass to one of the machine's own values, so the model chooses among what exists and can write nothing else. See `Docs/predict-agent.md`, A3.
struct TokenChoice {
    let vocabulary: TokenHealing.Vocabulary
    /// What remains to be written of each choice still open; a choice written whole frees the model.
    private(set) var remaining: [[UInt8]]
    /// Whether a choice has been written whole, after which every token is the model's own.
    private(set) var isFree = false

    init(vocabulary: TokenHealing.Vocabulary, choices: [String]) {
        self.vocabulary = vocabulary
        remaining = choices.map { Array($0.utf8) }.filter { !$0.isEmpty }
    }

    /// What a step adds to the logits: nothing for a token that keeps to some choice, minus infinity for the rest; nothing at all once a choice is written or when no token could keep to one.
    func mask(width: Int) -> [Float]? {
        guard !isFree else { return nil }
        let allowed = vocabulary.bytes.indices.map { id in
            Self.keeps(vocabulary.bytes[id], toOneOf: remaining)
        }
        guard allowed.contains(true) else { return nil }
        var mask = [Float](repeating: -.infinity, count: width)
        for (id, isAllowed) in allowed.enumerated() where isAllowed && id < width { mask[id] = 0 }
        return mask
    }

    /// Whether a token keeps to a choice: it writes part of one, or all of one and then a space.
    static func keeps(_ written: [UInt8], toOneOf choices: [[UInt8]]) -> Bool {
        guard !written.isEmpty else { return false }
        return choices.contains { choice in
            choice.starts(with: written)
                || (written.count > choice.count && written.starts(with: choice)
                    && TokenHealing.Vocabulary.isSpace(written[choice.count]))
        }
    }

    /// Advances every choice by the bytes one token wrote, dropping those it left; a choice written whole frees the model.
    mutating func took(_ written: [UInt8]) {
        guard !isFree else { return }
        var still: [[UInt8]] = []
        for choice in remaining {
            if choice.starts(with: written) {
                still.append(Array(choice.dropFirst(written.count)))
            } else if written.starts(with: choice) {
                still.append([])
            }
        }
        remaining = still
        // A choice written whole, or a token the mask should have refused, leaves nothing to hold the model to.
        if still.isEmpty || still.contains(where: \.isEmpty) { isFree = true }
    }

    /// Advances by one token's text, kept apart from the model so a test can drive it.
    mutating func took(_ text: String) { took(Array(text.utf8)) }
}
