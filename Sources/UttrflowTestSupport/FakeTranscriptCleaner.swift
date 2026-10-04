// A TranscriptCleaning that tidies as scripted and records every request.
public import UttrflowCore
public import struct Foundation.UUID
private import Synchronization

/// A ``TranscriptCleaning`` that records each request, answers as scripted, and takes the scripted time.
public final class FakeTranscriptCleaner: TranscriptCleaning, Sendable {
    /// How the cleaner answers a request.
    private enum Answer: Sendable {
        case scripted(ScriptedSequence<TransformationResult, TransformationError>)
        case tidying(@Sendable (String) -> String, producedBy: TransformerKind, entriesTaken: [UUID])
    }

    private struct State: Sendable {
        var answer: Answer
        var requests: [TransformationRequest] = []
    }

    private let state: Mutex<State>
    private let takes: ScriptedDuration
    private let holding: (@Sendable () async -> Void)?

    /// A cleaner that answers each request with the next of `outcomes`.
    public init(
        answering outcomes: ScriptedSequence<TransformationResult, TransformationError>,
        takes: ScriptedDuration = .instant,
        holding: (@Sendable () async -> Void)? = nil
    ) {
        state = Mutex(State(answer: .scripted(outcomes)))
        self.takes = takes
        self.holding = holding
    }

    /// A cleaner that answers every request with its words passed through `tidy`, by default unchanged.
    public init(
        tidying tidy: @escaping @Sendable (String) -> String = { $0 },
        producedBy kind: TransformerKind = .rules,
        taking entries: [UUID] = [],
        takes: ScriptedDuration = .instant
    ) {
        state = Mutex(State(answer: .tidying(tidy, producedBy: kind, entriesTaken: entries)))
        self.takes = takes
        holding = nil
    }

    public func clean(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        let outcome = state.withLock { state -> ScriptedOutcome<TransformationResult, TransformationError> in
            state.requests.append(request)
            switch state.answer {
            case .scripted(var outcomes):
                defer { state.answer = .scripted(outcomes) }
                return outcomes.next()
            case .tidying(let tidy, let kind, let entries):
                return .success(
                    TransformationResult(
                        text: tidy(request.transcription.text), producedBy: kind, entriesTaken: entries))
            }
        }
        await takes.elapse()
        await holding?()
        return try outcome.resolve()
    }

    /// Every request the pipeline sent, in order.
    public var requests: [TransformationRequest] { state.withLock { $0.requests } }
}
