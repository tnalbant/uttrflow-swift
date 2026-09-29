// Per-stage time limits, and the race that enforces one without waiting on a stage that hangs.

private import Synchronization

/// How long a dictation waits for one stage before giving up. See `Docs/stuck-recording.md`.
public enum StageTimeout: Sendable {
    /// Transcription, generous because a cold model load and four minutes of audio are both honest.
    public static let transcription = Duration.seconds(120)

    /// The whole tidying stage, as a backstop; each engine on the route has its own allowance inside it.
    public static let transformation = Duration.seconds(30)

    /// What one model engine may take before the router steps past it, leaving the floor room inside the stage.
    public static let engine = Duration.seconds(20)

    /// What the deterministic floor may take; it only rearranges words already in hand.
    public static let rules = Duration.seconds(2)

    /// Context, correction, expansion and insertion: local, but each can block on another app.
    public static let quick = Duration.seconds(15)

    /// Loading the speech model: about twice the slowest measured cold load, 154 s. See `Docs/startup.md`.
    public static let speechModelLoad = Duration.seconds(300)
}

/// Runs `work`, answering `nil` when `limit` wins; the work is cancelled then, not awaited, since it may hang.
public func withStageTimeout<Success: Sendable>(
    _ limit: Duration,
    clock: any Clock<Duration>,
    _ work: @escaping @Sendable () async throws -> Success
) async throws -> Success? {
    let race = StageRace<Success>()
    await withTaskCancellationHandler {
        await withCheckedContinuation { continuation in
            race.arm(continuation)
            race.start(clock: clock, limit: limit, work: work)
        }
    } onCancel: {
        race.finish(.cancelled)
    }
    return try race.result()
}

/// The work's answer if it arrives within `allowance` (at least 1 ms), else `nil`, the work cancelled and not awaited.
public func withDeadline<Answer: Sendable>(
    _ allowance: Duration,
    clock: any Clock<Duration> = ContinuousClock(),
    _ work: @escaping @Sendable () async -> Answer?
) async -> Answer? {
    let answer = try? await withStageTimeout(max(allowance, .milliseconds(1)), clock: clock) { await work() }
    return answer ?? nil
}

/// Whichever of a stage and its limit answered first, and what it answered.
private final class StageRace<Success: Sendable>: Sendable {
    /// What the winner answered.
    enum Outcome: Sendable {
        case finished(Success)
        case failed(any Error)
        case expired
        case cancelled
    }

    /// The waiting caller and the first answer, kept together under one lock.
    private struct State {
        var waiting: CheckedContinuation<Void, Never>?
        var outcome: Outcome?
        var timer: Task<Void, Never>?
        var working: Task<Void, Never>?
    }

    private let state = Mutex(State())

    /// Parks the caller until the first answer.
    func arm(_ continuation: CheckedContinuation<Void, Never>) {
        let resume = state.withLock { state -> Bool in
            guard state.outcome == nil else { return true }
            state.waiting = continuation
            return false
        }
        if resume { continuation.resume() }
    }

    /// Starts both racers, cancelling tasks immediately when an outcome already won.
    func start(
        clock: any Clock<Duration>, limit: Duration,
        work: @escaping @Sendable () async throws -> Success
    ) {
        state.withLock { state in
            guard state.outcome == nil else { return }
            state.working = Task {
                do { finish(.finished(try await work())) } catch { finish(.failed(error)) }
            }
            state.timer = Task { [clock] in
                try? await clock.sleep(for: limit)
                guard !Task.isCancelled else { return }
                finish(.expired)
            }
        }
    }

    /// Records an answer, and wakes the caller for the first one only.
    func finish(_ outcome: Outcome) {
        let completed = state.withLock {
            state -> (CheckedContinuation<Void, Never>?, Task<Void, Never>?, Task<Void, Never>?)? in
            guard state.outcome == nil else { return nil }
            state.outcome = outcome
            let completed = (state.waiting, state.timer, state.working)
            state.waiting = nil
            state.timer = nil
            state.working = nil
            return completed
        }
        guard let (waiting, timer, working) = completed else { return }
        timer?.cancel()
        working?.cancel()
        waiting?.resume()
    }

    /// The value, the error rethrown, or `nil` when the limit won.
    func result() throws -> Success? {
        switch state.withLock({ $0.outcome }) {
        case .finished(let value): value
        case .failed(let error): throw error
        case .expired, .cancelled, nil: nil
        }
    }
}
