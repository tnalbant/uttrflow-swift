import Foundation
import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// A recogniser that hears the same words in every piece.
private actor HearingSpeechEngine: SpeechEngine {
    let kind = SpeechEngineKind.whisperKit
    private let heard: String

    init(hearing heard: String) {
        self.heard = heard
    }

    func prepare() async throws(SpeechEngineError) {}

    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        Transcription(
            text: heard, detectedLanguage: DetectedLanguage(code: .hindi, confidence: 1),
            audioDuration: audio.duration)
    }
}

@Suite("Dictation pipeline: Latin letters only")
struct DictationPipelineLatinOutputTests {
    /// One short take, heard as `heard`, tidied by `cleaner`, and what was inserted.
    private func dictate(_ heard: String, cleaner: any TranscriptCleaning) async -> [String] {
        await dictate(heard, cleaner: cleaner, snippets: NoTextChanges())
    }

    /// One short take with the supplied snippet expander and what the inserter receives.
    private func dictate(
        _ heard: String, cleaner: any TranscriptCleaning, snippets: any SnippetExpanding
    ) async -> [String] {
        let rate = AudioSamples.canonicalSampleRate
        let take = AudioSamples.canonical(
            (0..<Int(1.2 * Double(rate))).map { 0.3 * Float(sin(Double($0) * 0.07)) })
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(take))
        await capture.setCaptured(take)
        let inserter = FakeTextInserter()
        let pipeline = DictationPipeline(
            capture: capture, speech: HearingSpeechEngine(hearing: heard), cleaner: cleaner,
            context: FakeContextEngine(context: .fixture()), inserter: inserter, snippets: snippets)
        await pipeline.startRecording()
        await pipeline.finishRecording()
        return inserter.received
    }

    @Test("romanises Devanagari that no tidier romanised, whether the tidy failed or handed the words back")
    func romanisesUntidiedDevanagari() async {
        for cleaner: any TranscriptCleaning in [FakeTranscriptCleaner(answering: ScriptedSequence(.failure(.noCapableTransformer))), FakeTranscriptCleaner(producedBy: .foundationModels)] {
            let inserted = await dictate("हाँ ठीक है।", cleaner: cleaner)
            #expect(inserted.count == 1)
            #expect(inserted.allSatisfy { !Romaniser.containsDevanagari($0) && LatinScript.isLatin($0) })
            #expect(inserted.first?.hasPrefix("Haan thik hai") == true, "\(inserted)")
        }
    }

    @Test("romanises Devanagari from a snippet before insertion")
    func romanisesSnippetExpansion() async {
        let snippet = Snippet(
            trigger: "greeting", expansion: "हाँ ठीक है", created: Date(timeIntervalSince1970: 0))
        let inserted = await dictate(
            "greeting", cleaner: FakeTranscriptCleaner(producedBy: .foundationModels), snippets: StoredSnippetExpander(snippet: snippet))

        #expect(inserted == ["Haan thik hai"])
        #expect(inserted.allSatisfy { !Romaniser.containsDevanagari($0) && LatinScript.isLatin($0) })
    }

    @Test("inserts romanised Hinglish on the shipping floor when the model is not there")
    func rulesFloorRomanises() async {
        let router = TransformerRouter(
            engines: [RuleBasedTransformer()], preference: [.foundationModels, .rules],
            rulesAlone: .shortReplies)
        let inserted = await dictate("मैं अभी आता हूँ", cleaner: router)
        #expect(inserted.count == 1)
        #expect(inserted.first?.hasPrefix("Main abhi aata hoon") == true, "\(inserted)")
    }

    @Test("writes another script in Latin letters rather than insert it")
    func transliteratesOtherScripts() async {
        let inserted = await dictate("Привет", cleaner: FakeTranscriptCleaner(producedBy: .foundationModels))
        #expect(inserted.count == 1)
        #expect(inserted.allSatisfy { LatinScript.isLatin($0) })
    }

    @Test(
        "inserts English exactly as the tidier wrote it",
        arguments: ["Okay, see you at 5 p.m. 👍", "Café “naïve” — résumé…", "x² ≤ ½, ₹1,50,000 and 3.5%"])
    func leavesEnglishAlone(text: String) async {
        #expect(await dictate(text, cleaner: FakeTranscriptCleaner(producedBy: .foundationModels)) == [text])
    }
}

/// Runs the production snippet matcher and adapts its result to the pipeline seam.
private struct StoredSnippetExpander: SnippetExpanding {
    let snippet: Snippet

    func expand(_ text: String) async -> ExpandedTranscript {
        let expansion = SnippetExpander(snippets: [snippet]).expand(text)
        return ExpandedTranscript(
            text: expansion.text,
            snippets: expansion.applied.map {
                SnippetUse(snippetID: $0.snippetID, matched: $0.matched, expansion: $0.expansion)
            })
    }
}
