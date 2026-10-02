import CoreMedia
import Speech
import Testing
import UttrflowAI
import UttrflowCore

@testable import UttrflowSpeech

@Suite("Apple speech vocabulary context")
struct AppleSpeechBackendTests {
    @Test("contextual strings preserve distinct words and discard blank entries")
    func contextualStrings() {
        #expect(
            AppleSpeechBackend.contextualStrings(for: [" Venkatesan ", "", "Grafana", "Grafana"])
                == ["Grafana", "Venkatesan"])
    }

    @Test("analyzer context receives the normalized vocabulary")
    func analyzerContext() {
        let context = AppleSpeechBackend.context(for: [" Venkatesan ", "Grafana", "Grafana"])
        #expect(context.contextualStrings[.general] == ["Grafana", "Venkatesan"])
    }

    @Test("a prepared analyzer is reused only for its exact vocabulary")
    func preparedVocabularyMustMatch() {
        let prepared = AppleSpeechBackend.PreparedPair(vocabulary: ["Grafana"], value: 42)

        let same = AppleSpeechBackend.takePreparedPair(prepared, matching: ["Grafana"])
        #expect(same.value == 42)
        #expect(same.remaining == nil)

        let changed = AppleSpeechBackend.takePreparedPair(prepared, matching: ["Venkatesan"])
        #expect(changed.value == nil)
        #expect(changed.remaining == nil)
    }

    @Test("requests the genuine confidence and audio-time attributes")
    func requestsWordAttributes() {
        let options = AppleSpeechBackend.transcriptionPreset().attributeOptions
        #expect(options.contains(.audioTimeRange))
        #expect(options.contains(.transcriptionConfidence))
    }

    @Test("maps Apple word attributes through Draft into CandidateSource")
    func appleConfidenceReachesCandidates() async throws {
        var text = AttributedString("pool request")
        try Self.attribute("pool", in: &text, confidence: 0.9, start: 0.1, end: 0.25)
        try Self.attribute("request", in: &text, confidence: 0.2, start: 0.3, end: 0.7)

        let audioRange = CMTimeRange(
            start: CMTime(seconds: 0, preferredTimescale: 600),
            duration: CMTime(seconds: 1, preferredTimescale: 600))
        let segment = try #require(AppleSpeechTranscriptMapping.segment(text, audioRange: audioRange))
        #expect(
            segment.words == [
                RawWord(text: "pool", start: 0.1, end: 0.25, probability: 0.9),
                RawWord(text: "request", start: 0.3, end: 0.7, probability: 0.2),
            ])

        let raw = RawTranscript(text: "pool request", segments: [segment])
        let transcript = raw.transcription(audioDuration: .seconds(1))
        let draft = Draft(transcription: transcript)
        #expect(draft.confidencesAreReal)
        #expect(draft.words.map(\.confidence) == [0.9, 0.2])

        let spans = await DoubtfulWords(sources: [AppleSpeechCandidates()])
            .spans(in: draft, for: .unknown)
        #expect(spans == [DoubtfulSpan(heard: "request", confidence: 0.2, candidates: ["recheck"])])
    }

    @Test("does not invent confidence when an Apple token lacks its attributes")
    func missingWordAttributesStayUnavailable() throws {
        var text = AttributedString("pool request")
        try Self.attribute("request", in: &text, confidence: 0.2, start: 0.3, end: 0.7)
        let audioRange = CMTimeRange(
            start: CMTime(seconds: 0, preferredTimescale: 600),
            duration: CMTime(seconds: 1, preferredTimescale: 600))

        let segment = try #require(AppleSpeechTranscriptMapping.segment(text, audioRange: audioRange))
        #expect(segment.words == nil)
        let transcript = RawTranscript(text: "pool request", segments: [segment])
            .transcription(audioDuration: .seconds(1))
        #expect(!Draft(transcription: transcript).confidencesAreReal)
    }

    private static func attribute(
        _ word: String, in text: inout AttributedString, confidence: Double, start: Double, end: Double
    ) throws {
        let range = try #require(text.range(of: word))
        text[range][AttributeScopes.SpeechAttributes.ConfidenceAttribute.self] = confidence
        text[range][AttributeScopes.SpeechAttributes.TimeRangeAttribute.self] = CMTimeRange(
            start: CMTime(value: Int64((start * 1_000).rounded()), timescale: 1_000),
            duration: CMTime(value: Int64(((end - start) * 1_000).rounded()), timescale: 1_000))
    }
}

private struct AppleSpeechCandidates: CandidateSource {
    func candidates(for word: Draft.Word, in situation: Situation) async -> [Reading] {
        word.text == "request" ? ["recheck"] : []
    }
}
