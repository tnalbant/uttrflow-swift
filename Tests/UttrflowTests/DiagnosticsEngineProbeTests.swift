// The Diagnostics page said "Not checked yet" forever, because nothing ever checked.

import Foundation
import Testing
import UttrflowCore
import UttrflowPipeline

@testable import Uttrflow

@MainActor
@Suite("The clean-up engines Diagnostics reports on", .timeLimit(.minutes(1)))
struct DiagnosticsEngineProbeTests {
    /// Starts the probe and waits for it to finish, which it does on a task of its own.
    private func probed(_ app: AppDelegate) async -> [TransformerKind: Bool] {
        await app.probeTransformers().value
        return app.transformerAvailability
    }

    /// #152: the snapshot's availability was never populated, so every row read `nil`.
    @Test("are asked, so the page has an answer rather than a pending check")
    func areAsked() async {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        #expect(app.transformerAvailability.isEmpty)

        let answered = await probed(app)
        #expect(!answered.isEmpty, "nothing was asked, so the page would say Not checked yet")
        // The floor can always run, whatever else this Mac has.
        #expect(answered[.rules] == true)
    }

    @Test("and every kind gets an answer, not only the ones that said yes")
    func everyKindIsAnswered() async {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        let answered = await probed(app)

        for kind in TransformerKind.allCases {
            #expect(answered[kind] != nil, "\(kind.rawValue) was left unanswered")
        }
    }

    /// #1668: the speech model row was never given an answer, so it read Not checked yet forever.
    @Test("the speech model is looked for on disk too")
    func speechModelIsLookedFor() async {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        #expect(app.speechModelPresence == nil)

        await app.probeSpeechModel().value
        #expect(app.speechModelPresence != nil, "the page would still say Not checked yet")
    }

    @Test("only a typed Apple Speech load failure marks its diagnostics card failed")
    func appleSpeechLoadFailureIsEngineScoped() {
        let apple = AppDelegate(container: Sandbox().root)
        let appleError = SpeechEngineError.modelLoadFailed(description: "unsupported locale")
        let appleFailure = DictationFailure(appleError, speechEngineKind: .appleSpeech)
        apple.render(.failed(appleFailure))

        #expect(appleFailure.speechEngineError == appleError)
        #expect(apple.appleSpeechLoadFailure == appleError)

        let whisper = AppDelegate(container: Sandbox().root)
        whisper.render(
            .failed(
                DictationFailure(
                    SpeechEngineError.modelLoadFailed(description: "fixture"),
                    speechEngineKind: .whisperKit)))
        #expect(whisper.appleSpeechLoadFailure == nil)

        let untyped = AppDelegate(container: Sandbox().root)
        untyped.render(
            .failed(
                DictationFailure(
                    message: appleError.userMessage, recovery: .retry, severity: .recoverable)))
        #expect(untyped.appleSpeechLoadFailure == nil)
    }
}
