// The correction engine over a dictionary, as the pipeline's word-correcting seam.
public import UttrflowCore
public import UttrflowDictionary
import UttrflowAI

/// The correction engine over the user's dictionary: mapping only, deciding none of it.
public struct DictionaryCorrections: WordCorrecting {
    /// The dictionary arranged by sound, read when a dictation fixes it.
    public typealias Indexing = @Sendable () async -> PhoneticIndex

    private let index: Indexing
    private let engine = WordCorrectionEngine()

    public init(index: @escaping Indexing) {
        self.index = index
    }

    /// The dictionary as it stands now; a word added or learnt meanwhile reaches the next dictation.
    public func fixed() async -> any WordCorrecting {
        let held = await index()
        return DictionaryCorrections { held }
    }

    public func corrections(
        for transcription: Transcription, seeing context: AppContext
    ) async -> [DictationCorrection] {
        await weigh(transcription, seeing: context).corrections
    }

    public func weigh(
        _ transcription: Transcription, seeing context: AppContext
    ) async -> WeighedCorrections {
        // No score, no judgement: Apple's recogniser reports none, so it gets no corrections.
        guard let scored = transcription.scoredWords else { return WeighedCorrections(corrections: []) }
        let utterance = Utterance(
            words: scored.map { SpokenWord(text: $0.text, confidence: $0.confidence) })

        let verdict = engine.verdict(for: utterance, against: await index(), seeing: context)

        return WeighedCorrections(
            corrections: verdict.proposals.map {
                DictationCorrection(
                    heard: $0.heard, wrote: $0.replacement, wordRange: $0.wordRange,
                    entryID: $0.entryID, reason: $0.reason,
                    heardConfidence: $0.heardConfidence)
            },
            held: verdict.held)
    }
}
