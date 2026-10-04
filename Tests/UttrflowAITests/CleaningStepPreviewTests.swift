import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("A settings preview of a clean-up step")
struct CleaningStepPreviewTests {
    @Test(
        "each offered step's preview is what the rules transformer writes, on and off",
        arguments: CleaningSteps.offered)
    func matchesTheTransformer(step: CleaningStep) async throws {
        let preview = CleaningStepPreview.of(step)
        let request = TransformationRequest(transcription: Transcription(text: step.example))
        let on = try await RuleBasedTransformer(steps: .default.setting(step.id, isOn: true))
            .transform(request).text
        let off = try await RuleBasedTransformer(steps: .default.setting(step.id, isOn: false))
            .transform(request).text
        #expect(preview.with == on)
        #expect(preview.without == off)
    }

    @Test("each offered step's example is changed by that step", arguments: CleaningSteps.offered)
    func exampleShowsTheStep(step: CleaningStep) {
        let preview = CleaningStepPreview.of(step)
        #expect(preview.with != preview.without)
    }

    @Test("the previews follow the offered steps in order and honour the other choices")
    func allInOrder() throws {
        let steps = CleaningSteps.default.setting(.fillers, isOn: false)
        let previews = CleaningStepPreview.all(steps: steps)
        #expect(previews.map(\.step) == CleaningSteps.offered.map(\.id))
        let stammers = try #require(CleaningSteps.step(.stammers))
        #expect(previews.contains(CleaningStepPreview.of(stammers, steps: steps)))
    }
}
