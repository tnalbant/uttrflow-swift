// The one way a fake scripts a run of answers and how long each call takes.

/// Outcomes a fake hands out one per call, in order, repeating the last once the run is spent.
public struct ScriptedSequence<Success: Sendable, Failure: Error>: Sendable {
    private var remaining: [ScriptedOutcome<Success, Failure>]
    private let last: ScriptedOutcome<Success, Failure>

    /// `first` answers the first call; each of `then` answers one more, and the final one answers every call after.
    public init(_ first: ScriptedOutcome<Success, Failure>, then: [ScriptedOutcome<Success, Failure>] = []) {
        remaining = [first] + then
        last = then.last ?? first
    }

    /// Successes in order, and `afterwards` for every call once they are spent; nil repeats the last success.
    public static func successes(
        _ values: [Success], afterwards: ScriptedOutcome<Success, Failure>? = nil
    ) -> Self {
        let outcomes = values.map { ScriptedOutcome<Success, Failure>.success($0) } + (afterwards.map { [$0] } ?? [])
        guard let first = outcomes.first else { preconditionFailure("a sequence answers at least one call") }
        return Self(first, then: Array(outcomes.dropFirst()))
    }

    /// The outcome for the next call.
    public mutating func next() -> ScriptedOutcome<Success, Failure> {
        remaining.isEmpty ? last : remaining.removeFirst()
    }
}

/// How long a fake's call takes, and on which clock, so a stage's cost is scripted beside its answer.
public struct ScriptedDuration: Sendable {
    private let pass: @Sendable () async -> Void

    private init(_ pass: @escaping @Sendable () async -> Void) {
        self.pass = pass
    }

    /// The call returns at once and costs nothing.
    public static let instant = ScriptedDuration {}

    /// The call costs `duration` on `clock` without waiting, as a stage the dictation was charged for.
    public static func charged(_ duration: Duration, to clock: ManualClock) -> ScriptedDuration {
        ScriptedDuration { clock.advance(by: duration) }
    }

    /// The call sleeps `duration` on `clock`, so whoever moves the clock decides when it returns.
    public static func slept<C: Clock>(
        _ duration: Duration, on clock: C
    ) -> ScriptedDuration where C.Duration == Duration {
        ScriptedDuration { try? await clock.sleep(for: duration) }
    }

    /// Spends the scripted time.
    public func elapse() async {
        await pass()
    }
}
