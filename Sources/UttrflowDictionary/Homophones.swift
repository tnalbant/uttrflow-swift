// The ordinary words that really are said the same way, which a sound key cannot tell from a collision.

internal import Foundation

/// Words pronounced alike, kept by hand because Double Metaphone files "main" with "man" as readily as "hear" with "here".
public enum Homophones {
    /// Whether two ordinary words are the same sound, which is what makes one a reading of the other.
    public static func share(_ word: String, _ other: String) -> Bool {
        let word = lookupKey(word)
        let other = lookupKey(other)
        guard word != other else { return false }
        return group(containing: word)?.contains(where: { lookupKey($0) == other }) == true
    }

    /// Returns the hand-kept sound-alike spellings for one word, including the word itself.
    public static func group(containing word: String) -> Set<String>? {
        let word = lookupKey(word)
        return groups.first { group in group.contains { lookupKey($0) == word } }
    }

    /// Keeps apostrophes inside a spelling, where they distinguish words such as "its" and "it's".
    static func lookupKey(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .filter { $0.isLetter || $0.isNumber || $0 == "'" }
            .trimmingCharacters(in: CharacterSet(charactersIn: "'"))
    }

    /// Sets said identically; a pair whose vowels differ at all — "main" and "man" — belongs in none of them.
    static let groups: [Set<String>] = [
        ["allowed", "aloud"], ["bored", "board"], ["brake", "break"], ["capital", "capitol"],
        ["by", "buy", "bye"], ["cache", "cash"], ["cell", "sell"], ["cent", "scent", "sent"],
        ["cite", "site", "sight"], ["complement", "compliment"], ["die", "dye"],
        ["fair", "fare"], ["ate", "eight"], ["flew", "flu"], ["flour", "flower"],
        ["for", "four"], ["hear", "here"], ["hole", "whole"], ["hour", "our"],
        ["its", "it's"], ["knew", "new"], ["knight", "night"], ["know", "no"],
        ["mail", "male"], ["made", "maid"], ["meat", "meet"], ["need", "knead"],
        ["one", "won"], ["pain", "pane"], ["pair", "pear"], ["peace", "piece"], ["peak", "peek"],
        ["plain", "plane"], ["principal", "principle"], ["rain", "reign", "rein"],
        ["road", "rode"], ["root", "route"], ["role", "roll"], ["sail", "sale"], ["scene", "seen"],
        ["sea", "see"], ["son", "sun"], ["stationary", "stationery"], ["steal", "steel"],
        ["tail", "tale"], ["their", "there", "they're"], ["threw", "through"], ["to", "too", "two"],
        ["toe", "tow"], ["vain", "vein"], ["wait", "weight"], ["way", "weigh"],
        ["wear", "where"], ["weather", "whether"], ["weak", "week"],
        ["wood", "would"], ["write", "right", "rite"],
        ["your", "you're"],
    ]
}
