public import UttrflowCore
private import UttrflowDictionary

/// The hand-kept homophone partners of a word in `Homophones.groups`, so a confidently wrong hearing can be reconsidered.
public struct HomophoneCandidates: CandidateSource {
    /// Every partner in the largest group, so a three-way group never drops the one that was meant.
    public static let maximumOffered = 2

    public init() {}

    public func candidates(for word: Draft.Word, in situation: Situation) async -> [Reading] {
        guard let group = Homophones.group(containing: word.text) else { return [] }
        return
            group
            .filter { Homophones.share($0, word.text) }
            .prefix(Self.maximumOffered)
            .map { Reading($0) }
    }
}
