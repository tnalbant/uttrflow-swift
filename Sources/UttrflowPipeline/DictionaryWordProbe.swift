// Trying one dictionary word: recognition only, with and without the entry, then the correction engine.
public import UttrflowCore
public import UttrflowDictionary
import Foundation

/// What one spoken try of a dictionary word showed, in the order the person can act on it.
public enum DictionaryProbeOutcome: Sendable, Equatable {
    /// The recogniser wrote the word once the entry was in its prompt.
    case recognisedFromStart
    /// The recogniser missed it, and the correction engine put the entry's spelling in.
    case recognisedAfterCorrection
    /// Neither wrote it; the words are what was heard, which a "Say it like" can be set to.
    case heardAs(String)
}

/// The two decodes and the correction a try ran, and the outcome they add up to.
public struct DictionaryProbeResult: Sendable, Equatable {
    /// The transcript with no dictionary words in the prompt.
    public let withoutEntry: String
    /// The transcript with the entry's spelling in the prompt.
    public let withEntry: String
    /// `withEntry` after the correction engine ran against the dictionary.
    public let corrected: String
    /// What the three add up to.
    public let outcome: DictionaryProbeOutcome

    /// Takes the transcripts and the outcome as given.
    public init(withoutEntry: String, withEntry: String, corrected: String, outcome: DictionaryProbeOutcome) {
        self.withoutEntry = withoutEntry
        self.withEntry = withEntry
        self.corrected = corrected
        self.outcome = outcome
    }
}

/// Recognition only: it inserts nothing, saves nothing and keeps no audio, so a try leaves no trace.
public struct DictionaryWordProbe: Sendable {
    private let speech: any SpeechEngine
    private let corrector: any WordCorrecting

    /// A probe over a recogniser and the corrector the dictation path uses.
    public init(speech: any SpeechEngine, corrector: any WordCorrecting) {
        self.speech = speech
        self.corrector = corrector
    }

    /// A probe whose dictionary is `entries`, through the same correction engine dictation uses.
    public init(speech: any SpeechEngine, dictionary entries: [DictionaryEntry]) {
        let index = PhoneticIndex(entries: entries)
        self.init(speech: speech, corrector: DictionaryCorrections(index: { index }))
    }

    /// Decodes `audio` without and with `entry` in the prompt, corrects the second, and says which wrote the word.
    public func probe(
        _ audio: AudioSamples, for entry: DictionaryEntry, language: LanguageCode? = nil
    ) async throws(SpeechEngineError) -> DictionaryProbeResult {
        let without = try await speech.transcribe(
            audio, options: TranscriptionOptions(languageHint: language, vocabulary: []))
        let with = try await speech.transcribe(
            audio, options: TranscriptionOptions(languageHint: language, vocabulary: [entry.word]))
        let proposals = (try? await corrector.corrections(for: with, seeing: AppContext())) ?? []
        let corrected = DictationCorrection.applying(proposals, to: with.text).text
        return DictionaryProbeResult(
            withoutEntry: without.text, withEntry: with.text, corrected: corrected,
            outcome: Self.outcome(of: entry, heard: with.text, corrected: corrected))
    }

    /// Which stage wrote the entry's spelling, judged by whole words so "Quillons" is not "Quillon".
    static func outcome(of entry: DictionaryEntry, heard: String, corrected: String) -> DictionaryProbeOutcome
    {
        if writes(entry, in: heard) { return .recognisedFromStart }
        if writes(entry, in: corrected) { return .recognisedAfterCorrection }
        return .heardAs(heard.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Whether the entry's spelling appears in `text` as a run of whole words.
    private static func writes(_ entry: DictionaryEntry, in text: String) -> Bool {
        let wanted = keys(entry.word)
        let words = keys(text)
        guard !wanted.isEmpty, wanted.count <= words.count else { return false }
        return (0...(words.count - wanted.count)).contains {
            Array(words[$0..<($0 + wanted.count)]) == wanted
        }
    }

    /// Each word's spelling key, so case and the recogniser's punctuation do not count.
    private static func keys(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map { DictionaryEntry.spellingKey(for: String($0)) }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".-/")) }.filter { !$0.isEmpty }
    }
}
