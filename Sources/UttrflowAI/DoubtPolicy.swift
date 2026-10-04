// The one rule for whether a heard word is doubted, which every consumer of doubt asks.
import UttrflowDictionary

/// Whether a word is doubted and why; the engine, the rules, the doubtful-words prompt and the guard all ask it. See Docs/cleanup.md.
public enum DoubtPolicy {
    /// Below this a word may be replaced; at or above it a word may corroborate, so none vouches for itself.
    public static let certaintyThreshold = 0.5

    /// Whether the recogniser scored a word surely enough to corroborate and to refuse a sound-alike swap.
    public static func isHeardSurely(_ confidence: Double) -> Bool {
        confidence >= certaintyThreshold
    }

    /// Why one word is doubted, or `nil` when it is not: a low score first, else membership of a homophone group.
    public static func reason(text: String, confidence: Double) -> DoubtReason? {
        if !isHeardSurely(confidence) { return .lowScore }
        return Homophones.group(containing: text) == nil ? nil : .homophoneClass
    }
}
