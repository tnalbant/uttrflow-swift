import Foundation
import Testing
import UttrflowTestSupport

@testable import UttrflowCore

/// One Devanagari word built from the romaniser's own tables, kept as parts so its spelling variants can be written.
struct GeneratedWord: CustomStringConvertible {
    /// A written piece of the word: a scalar, or a letter whose nukta may be written precomposed.
    enum Part {
        case scalar(Unicode.Scalar)
        case nuktaLetter(Unicode.Scalar)
        case nasal
    }

    let parts: [Part]
    let seed: Int

    /// The word spelled with decomposed nukta, anusvara and no joiners.
    var plain: String { written(precomposed: false, candrabindu: false, joiners: [:]) }

    var description: String {
        "\(seed) word \(plain.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " "))"
    }

    /// The word written one way: nukta letters precomposed or not, nasals as candrabindu or anusvara, joiners after the given parts.
    func written(precomposed: Bool, candrabindu: Bool, joiners: [Int: Unicode.Scalar]) -> String {
        var scalars = String.UnicodeScalarView()
        for (index, part) in parts.enumerated() {
            switch part {
            case .scalar(let scalar):
                scalars.append(scalar)
            case .nuktaLetter(let base):
                if precomposed, let single = Self.precomposed[base] {
                    scalars.append(single)
                } else {
                    scalars.append(base)
                    scalars.append(Romaniser.nukta)
                }
            case .nasal:
                scalars.append(candrabindu ? Romaniser.candrabindu : Romaniser.anusvara)
            }
            if let joiner = joiners[index] { scalars.append(joiner) }
        }
        return String(scalars)
    }

    /// Each base letter's precomposed nukta form, read from the romaniser's table.
    static let precomposed = Dictionary(
        Romaniser.precomposedNukta.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })

    private static let consonants = Romaniser.consonants.keys.sorted()
    private static let independentVowels = Romaniser.independentVowels.keys.sorted()
    private static let vowelSigns = Romaniser.vowelSigns.keys.sorted()

    /// A word of one to five syllables, each a consonant cluster or an independent vowel with its signs.
    init(_ random: inout Seeded, seed: Int) {
        self.seed = seed
        var parts: [Part] = []
        for _ in 0..<Int.random(in: 1...5, using: &random) {
            if random.chance(0.15) {
                parts.append(.scalar(random.pick(Self.independentVowels)))
            } else {
                for index in 0..<(random.chance(0.2) ? 2 : 1) {
                    if index > 0 { parts.append(.scalar(Romaniser.virama)) }
                    let letter = random.pick(Self.consonants)
                    let nukta = Romaniser.nuktaSounds[letter] != nil && random.chance(0.15)
                    parts.append(nukta ? .nuktaLetter(letter) : .scalar(letter))
                }
                if random.chance(0.1) {
                    parts.append(.scalar(Romaniser.virama))
                } else if random.chance(0.6) {
                    parts.append(.scalar(random.pick(Self.vowelSigns)))
                }
            }
            if random.chance(0.15) { parts.append(.nasal) }
            if random.chance(0.05) { parts.append(.scalar(Romaniser.visarga)) }
        }
        self.parts = parts
    }
}

/// Invariants of the romaniser's output that hold for every word, over words generated from its tables. See `Docs/latin-output.md`.
@Suite("Romaniser properties")
struct RomaniserPropertyTests {
    static let wordsPerSeed = 1_000

    /// The words one seed generates.
    static func words(seed: Int) -> [GeneratedWord] {
        var random = Seeded(seed: seed)
        return (0..<wordsPerSeed).map { _ in GeneratedWord(&random, seed: seed) }
    }

    static let seeds = Seeded.seeds(1...5)

    @Test("a word is written in lower-case ASCII letters and is never empty", arguments: seeds)
    func asciiLettersOnly(seed: Int) {
        for word in Self.words(seed: seed) {
            let romanised = Romaniser.romanised(word.plain)
            #expect(!romanised.isEmpty, "\(word)")
            #expect(
                romanised.unicodeScalars.allSatisfy { ("a"..."z").contains($0) },
                "\(word) -> \(romanised)")
        }
    }

    @Test("the enforced text is Latin and enforcing it again changes nothing", arguments: seeds)
    func enforcedIsLatinAndStable(seed: Int) {
        for word in Self.words(seed: seed) {
            let once = LatinScript.enforced(word.plain)
            #expect(LatinScript.isLatin(once), "\(word) -> \(once)")
            #expect(LatinScript.enforced(once) == once, "\(word) -> \(once)")
        }
    }

    @Test("nukta, nasal and joiner spellings of one word are written alike", arguments: seeds)
    func spellingVariantsAgree(seed: Int) {
        var random = Seeded(seed: seed)
        for word in Self.words(seed: seed) {
            let expected = Romaniser.romanised(word.plain)
            let joiners = Dictionary(
                uniqueKeysWithValues: word.parts.indices.filter { _ in random.chance(0.3) }.map {
                    ($0, random.pick([Romaniser.zeroWidthJoiner, Romaniser.zeroWidthNonJoiner]))
                })
            for precomposed in [false, true] {
                for candrabindu in [false, true] {
                    let variant = word.written(
                        precomposed: precomposed, candrabindu: candrabindu, joiners: joiners)
                    let romanised = Romaniser.romanised(variant)
                    #expect(romanised == expected, "\(word) variant \(variant) -> \(romanised)")
                    #expect(Romaniser.soundKey(romanised) == Romaniser.soundKey(expected), "\(word)")
                }
            }
        }
    }

    @Test("a run of words is written word for word with its spacing kept", arguments: seeds)
    func wordsKeepTheirSpacing(seed: Int) {
        var random = Seeded(seed: seed)
        let words = Self.words(seed: seed)
        var start = 0
        while start < words.count {
            let run = words[start..<min(words.count, start + Int.random(in: 1...6, using: &random))]
            start += run.count
            let separators = run.dropLast().map { _ in random.pick([" ", "  ", ", ", "\n", "\t"]) }
            var text = ""
            var expected = ""
            for (index, word) in run.enumerated() {
                text += word.plain
                expected += Romaniser.romanised(word.plain)
                if index < separators.count {
                    text += separators[index]
                    expected += separators[index]
                }
            }
            #expect(Romaniser.romanised(text) == expected, "seed \(seed) text \(text)")
        }
    }
}
