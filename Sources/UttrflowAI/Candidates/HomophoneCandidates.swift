public import UttrflowCore
private import UttrflowDictionary

/// The hand-kept homophone partners of a word in `Homophones.groups`, so a confidently wrong hearing can be reconsidered.
public struct HomophoneCandidates: CandidateSource {
    /// The one partner a homophone word has in the table.
    public static let maximumOffered = 1

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
