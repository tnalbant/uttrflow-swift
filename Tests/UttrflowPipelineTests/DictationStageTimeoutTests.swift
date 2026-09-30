// Tests that a stage which never returns is timed out.
import Synchronization
import Testing
import UttrflowInput
import struct Foundation.Data

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

private func suspendUntilCancelled() async {
    while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(3600))
    }
}

/// A ``SpeechEngine`` that accepts the audio and never answers.
private actor NeverAnsweringSpeechEngine: SpeechEngine {
    let kind = SpeechEngineKind.whisperKit

    func prepare() async throws(SpeechEngineError) {}

    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        // Suspends for ever, the way a wedged decoder does. Nothing resumes this.
        await suspendUntilCancelled()
        return .fixture()
    }
}

/// A ``TranscriptCleaning`` that tidies, so a test can watch a different stage.
private struct TimeoutTestCleaner: TranscriptCleaning {
    func clean(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        TransformationResult(text: "Tidied.", producedBy: .rules)
    }
}

/// A ``TextInserting`` that records what reached the screen.
private final class TimeoutTestInserter: TextInserting, Sendable {
    private let placed = Mutex<[String]>([])

    func insert(_ text: String) async throws(TextInsertionError) -> InsertionAttempt {
        placed.withLock { $0.append(text) }
        return InsertionAttempt(.accessibility)
    }

    var inserted: [String] { placed.withLock { $0 } }
}

/// A ``TranscriptCleaning`` that accepts the text and never answers.
private struct NeverAnsweringCleaner: TranscriptCleaning {
    func clean(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        await suspendUntilCancelled()
        return TransformationResult(text: request.transcription.text, producedBy: .rules)
    }
}

/// The first insertion strategy never returns, so the clipboard fallback cannot start.
private struct NeverAnsweringEngine: TextInsertionEngine {
    let method: TextInsertionMethod = .accessibility

    func canInsert() async -> Bool { true }

    func insert(_ text: String) async throws(TextInsertionError) -> InsertionArrival {
        await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
        return .notReported
    }
}

/// A ``TextInserting`` that takes the text and never answers, the way a hung application does.
private struct NeverAnsweringInserter: TextInserting {
    func insert(_ text: String) async throws(TextInsertionError) -> InsertionAttempt {
        await suspendUntilCancelled()
        return InsertionAttempt(.accessibility)
    }
}

/// A ``TextInserting`` that never confirms a copy.
private struct NeverAnsweringClipboard: TextInserting {
    func insert(_ text: String) async throws(TextInsertionError) -> InsertionAttempt {
        await suspendUntilCancelled()
        return InsertionAttempt(.clipboard)
    }
}

private final class TimeoutPasteboard: Pasteboard, Sendable {
    private let stored = Mutex<String?>("older copied text")

    func text() -> String? { stored.withLock { $0 } }
    func setText(_ text: String) { stored.withLock { $0 = text } }
    func setConcealedText(_ text: String) { setText(text) }
    func setImage(_ data: Data) { stored.withLock { $0 = nil } }
}

@Suite("Dictation pipeline: a stage that never answers", .timeLimit(.minutes(1)))
struct DictationStageTimeoutTests {
    /// Reaches `stage`, then fires its own timer once it is set, never advancing after the stage has ended.
    private func expire(
        _ limit: Duration, at stage: DictationState, of pipeline: DictationPipeline,
        on clock: ManualClock
    ) async {
        while !Task.isCancelled, await pipeline.currentState != stage { await Task.yield() }
        while !Task.isCancelled, await pipeline.currentState == stage {
            if clock.advanceIfSomethingIsWaiting(exactly: limit) { return }
            await Task.yield()
        }
    }

    /// Waits for `finishing`, or stops waiting once the test is cancelled, so the time limit can end a wedged run.
    private func settle(_ finishing: Task<Void, Never>) async {
        let waiting = Mutex<(continuation: CheckedContinuation<Void, Never>?, done: Bool)>((nil, false))
        let wake: @Sendable () -> Void = {
            waiting.withLock { state -> CheckedContinuation<Void, Never>? in
                state.done = true
                defer { state.continuation = nil }
                return state.continuation
            }?.resume()
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let parked = waiting.withLock { state -> Bool in
                    guard !state.done, !Task.isCancelled else { return false }
                    state.continuation = continuation
                    return true
                }
                guard parked else { return continuation.resume() }
                Task {
                    await finishing.value
                    wake()
                }
            }
        } onCancel: {
            wake()
        }
    }

    @Test("a recogniser that never answers ends the dictation instead of wedging it")
    func transcriptionThatNeverAnswers() async {
        let clock = ManualClock()
        let metrics = RecordingMetricsRecorder()
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(.silence(seconds: 2))),
            speech: NeverAnsweringSpeechEngine(),
            cleaner: TimeoutTestCleaner(),
            context: FakeContextEngine(),
            inserter: TimeoutTestInserter(),
            metrics: metrics,
            clock: clock)

        await pipeline.startRecording()
        let finishing = Task { await pipeline.finishRecording() }
        await expire(StageTimeout.transcription, at: .transcribing, of: pipeline, on: clock)
        await settle(finishing)

        guard case .failed = await pipeline.currentState else {
            Issue.record("expected the dictation to fail, got \(await pipeline.currentState)")
            return
        }
        // The point of the whole thing: not busy, so the next dictation can start.
        #expect(await pipeline.currentState.isBusy == false)
        // An expired stage is a failed one, or the failure counts never see a hung recogniser.
        #expect(await metrics.measurements(for: .transcription).map(\.succeeded) == [false])
    }

    @Test("a dictation can begin again after a stage timed out")
    func recoversForTheNextDictation() async {
        let clock = ManualClock()
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(.silence(seconds: 2))),
            speech: NeverAnsweringSpeechEngine(),
            cleaner: TimeoutTestCleaner(),
            context: FakeContextEngine(),
            inserter: TimeoutTestInserter(),
            clock: clock)

        await pipeline.startRecording()
        let finishing = Task { await pipeline.finishRecording() }
        await expire(StageTimeout.transcription, at: .transcribing, of: pipeline, on: clock)
        await settle(finishing)

        await pipeline.startRecording()
        #expect(await pipeline.currentState == .recording)
    }

    @Test("a tidier that never answers costs the tidying, never the words")
    func tidyingThatNeverAnswers() async {
        let clock = ManualClock()
        let metrics = RecordingMetricsRecorder()
        let inserter = TimeoutTestInserter()
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(.silence(seconds: 2))),
            speech: FakeSpeechEngine(
                transcribeOutcome: .success(Transcription(text: "what I said"))),
            cleaner: NeverAnsweringCleaner(),
            context: FakeContextEngine(),
            inserter: inserter,
            metrics: metrics,
            clock: clock)

        await pipeline.startRecording()
        let finishing = Task { await pipeline.finishRecording() }
        await expire(StageTimeout.transformation, at: .tidying, of: pipeline, on: clock)
        await settle(finishing)

        // Untidied but inserted: §19 says tidying's failure never costs the words.
        #expect(inserter.inserted == ["what I said"])
        guard case .inserted = await pipeline.currentState else {
            Issue.record("expected the words to land, got \(await pipeline.currentState)")
            return
        }
        // The words still landed, and the tidying is still counted as the failure it was.
        #expect(await metrics.measurements(for: .transformation).map(\.succeeded) == [false])
        #expect(await metrics.measurements(for: .insertion).map(\.succeeded) == [true])
    }

    @Test("an application that never takes the words fails the dictation and counts the insertion failed")
    func insertionThatNeverAnswers() async {
        let clock = ManualClock()
        let metrics = RecordingMetricsRecorder()
        let pasteboard = TimeoutPasteboard()
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(.silence(seconds: 2))),
            speech: FakeSpeechEngine(
                transcribeOutcome: .success(Transcription(text: "what I said"))),
            cleaner: TimeoutTestCleaner(),
            context: FakeContextEngine(),
            inserter: TextInsertionCoordinator(strategies: [
                NeverAnsweringEngine(), ClipboardTextInsertionEngine(pasteboard: pasteboard),
            ]),
            metrics: metrics,
            clock: clock)

        await pipeline.startRecording()
        let finishing = Task { await pipeline.finishRecording() }
        await expire(StageTimeout.quick, at: .inserting, of: pipeline, on: clock)
        await settle(finishing)

        guard case .failed(let failure) = await pipeline.currentState else {
            Issue.record("expected the dictation to fail, got \(await pipeline.currentState)")
            return
        }
        #expect(failure.transcript == "Tidied.")
        #expect(failure.recovery == .showRecentDictations)
        #expect(failure.message.contains("Recent"))
        #expect(!failure.message.contains("copied"))
        #expect(!failure.message.contains("⌘V"))
        #expect(pasteboard.text() == "older copied text")
        #expect(await metrics.measurements(for: .insertion).map(\.succeeded) == [false])
        #expect(await metrics.measurements(for: .transcription).map(\.succeeded) == [true])

        // A hung application must not take the next dictation down with the one it never answered.
        await pipeline.startRecording()
        #expect(await pipeline.currentState == .recording)
    }

    @Test("a copy that never answers reports a clipboard failure, not an application timeout")
    func copyThatNeverAnswers() async {
        let clock = ManualClock()
        let recording = KeptRecording(id: UUID(), when: Date(), duration: .seconds(2))
        let recordings = FakeRecordingKeeper(
            waiting: [recording], audioOutcome: .success(.silence(seconds: 2)))
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(),
            speech: FakeSpeechEngine(
                transcribeOutcome: .success(Transcription(text: "what I said"))),
            cleaner: TimeoutTestCleaner(),
            context: FakeContextEngine(),
            inserter: TimeoutTestInserter(),
            recordings: recordings,
            clipboard: NeverAnsweringClipboard(),
            clock: clock)

        let retrying = Task { await pipeline.retry(recording.id) }
        await expire(.seconds(2), at: .inserting, of: pipeline, on: clock)
        await retrying.value

        guard case .failed(let failure) = await pipeline.currentState else {
            Issue.record("expected the copy to fail, got \(await pipeline.currentState)")
            return
        }
        #expect(failure.message == TextInsertionError.clipboardUnavailable.userMessage)
        #expect(failure.recovery == .showRecentDictations)
    }

    /// The words are the only thing left when the application will not take them, so the failure carries them.
    @Test("the words a hung application never took are still offered, untidied or not")
    func insertionTimeoutKeepsTheWords() async {
        let clock = ManualClock()
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(.silence(seconds: 2))),
            speech: FakeSpeechEngine(
                transcribeOutcome: .success(Transcription(text: "what I said"))),
            cleaner: NeverAnsweringCleaner(),
            context: FakeContextEngine(),
            inserter: NeverAnsweringInserter(),
            clock: clock)

        await pipeline.startRecording()
        let finishing = Task { await pipeline.finishRecording() }
        await expire(StageTimeout.transformation, at: .tidying, of: pipeline, on: clock)
        await expire(StageTimeout.quick, at: .inserting, of: pipeline, on: clock)
        await settle(finishing)

        guard case .failed(let failure) = await pipeline.currentState else {
            Issue.record("expected the dictation to fail, got \(await pipeline.currentState)")
            return
        }
        // Tidying timed out too, so what is offered is what the recogniser heard.
        #expect(failure.transcript == "what I said")
        #expect(await pipeline.currentState.isBusy == false)
    }
}
