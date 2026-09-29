/// The outcome of running an operation across a list of candidates.
public enum FallbackOutcome<Success: Sendable>: Sendable {
    /// The first candidate that worked, what it produced, and why the ones before it did not.
    case succeeded(Success, afterFailing: [any Error])
    /// Every candidate was tried and every one failed, in order.
    case exhausted(errors: [any Error])
}

/// Tries an operation against candidates in preference order; the one retry-and-degrade loop in the pipeline.
public enum FallbackRunner {
    /// Runs `attempt` on each candidate until one succeeds; an empty list is exhausted with no errors.
    public static func firstSuccess<Candidate, Success: Sendable>(
        among candidates: [Candidate],
        stopAfterFailure: (any Error) -> Bool = { _ in false },
        attempt: (Candidate) async throws -> Success
    ) async -> FallbackOutcome<Success> {
        var errors: [any Error] = []
        errors.reserveCapacity(candidates.count)

        for candidate in candidates {
            do {
                return .succeeded(try await attempt(candidate), afterFailing: errors)
            } catch {
                errors.append(error)
                if stopAfterFailure(error) { return .exhausted(errors: errors) }
            }
        }

        return .exhausted(errors: errors)
    }
}
