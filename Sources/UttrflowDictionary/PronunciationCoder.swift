// How a spelling is addressed in the index, for the spellings Double Metaphone cannot speak.

internal import Foundation
import UttrflowCore

/// Every key a spelling is filed and looked up under, so no entry is stored at an address nothing reaches.
public enum PronunciationCoder {
    /// Double Metaphone where the spelling has English letters in it; the folded spelling where it has none. A Devanagari spelling also gets the keys of its romanisation, so a Latin dictionary entry meets it too.
    public static func keys(for text: String) -> [String] {
        keys(for: text, sounding: DoubleMetaphone.code(for: text))
    }

    /// The keys for `text`, given the Double Metaphone code its caller already made for it.
    static func keys(for text: String, sounding sound: PhoneticCode) -> [String] {
        var keys = Set(baseKeys(for: text, sounding: sound))
        if Romaniser.containsDevanagari(text) {
            let romanised = Romaniser.romanised(text)
            keys.formUnion(baseKeys(for: romanised, sounding: DoubleMetaphone.code(for: romanised)))
        }
        return Array(keys)
    }

    /// The keys for one spelling as written, with no regard for what script it is in.
    private static func baseKeys(for text: String, sounding sound: PhoneticCode) -> [String] {
        guard sound.isSilent else { return sound.keys }
        let spelling = spellingKey(for: text)
        return spelling.isEmpty ? [] : [spelling]
    }

    /// The spelling itself as one key: Devanagari variants folded, case and accents folded away, and everything but letters and digits dropped.
    static func spellingKey(for text: String) -> String {
        let folded = Romaniser.scriptFolded(text)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return String(folded.unicodeScalars.filter(CharacterSet.alphanumerics.contains))
    }
}
