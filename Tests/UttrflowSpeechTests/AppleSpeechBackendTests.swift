import Testing

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
}
