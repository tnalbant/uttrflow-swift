import Foundation
import Testing

@testable import UttrflowPredict

/// One key, so a test says what it is varying rather than repeating what it is not.
private func key(_ candidate: String, _ context: String = "terminal") -> VerdictCache.Key {
    VerdictCache.Key(candidate: candidate, context: context)
}

@Suite("Verdicts already reached")
struct VerdictCacheTests {
    @Test("A verdict comes back for the candidate and context that produced it.")
    func remembers() {
        var cache = VerdictCache()
        let now = ContinuousClock.now
        cache.remember(.attested, for: key("git commit"), now: now)
        #expect(cache.verdict(for: key("git commit"), now: now) == .attested)
    }

    @Test("The same candidate in another context is a different question.")
    func contextIsPartOfTheKey() {
        var cache = VerdictCache()
        let now = ContinuousClock.now
        cache.remember(.attested, for: key("git commit", "terminal"), now: now)
        #expect(cache.verdict(for: key("git commit", "editor"), now: now) == nil)
    }

    @Test("Another candidate in the same context is a different question too.")
    func candidateIsPartOfTheKey() {
        var cache = VerdictCache()
        let now = ContinuousClock.now
        cache.remember(.attested, for: key("git commit"), now: now)
        #expect(cache.verdict(for: key("git checkout"), now: now) == nil)
    }

    @Test("A verdict stops being believed once its lifetime has passed.")
    func expires() {
        var cache = VerdictCache()
        let now = ContinuousClock.now
        cache.remember(.corrected("git commit"), for: key("git comit"), now: now)
        #expect(cache.verdict(for: key("git comit"), now: now + .seconds(6)) == nil)
    }

    @Test("A backward wall-clock jump cannot extend a verdict's monotonic lifetime.")
    func expiresDespiteWallClockGoingBackward() {
        var cache = VerdictCache()
        let insertedAt = ContinuousClock.now
        let dateBeforeInsertion = moment.addingTimeInterval(-3_600)
        cache.remember(.attested, for: key("git commit"), now: insertedAt)

        #expect(dateBeforeInsertion < moment)
        #expect(cache.verdict(for: key("git commit"), now: insertedAt + .seconds(6)) == nil)
    }

    @Test("Remembering again discards what has expired rather than spending capacity on it.")
    func expiredEntriesAreDropped() {
        var cache = VerdictCache()
        let now = ContinuousClock.now
        cache.remember(.attested, for: key("git commit"), now: now)
        #expect(cache.count == 1)
        cache.remember(.attested, for: key("git checkout"), now: ContinuousClock.now + .seconds(6))
        #expect(cache.count == 1)
    }

    @Test("Remembering the same key again replaces the verdict rather than growing the cache.")
    func replacesInPlace() {
        var cache = VerdictCache()
        let now = ContinuousClock.now
        cache.remember(.plausible, for: key("git comit"), now: now)
        cache.remember(.corrected("git commit"), for: key("git comit"), now: now)
        #expect(cache.count == 1)
        #expect(cache.verdict(for: key("git comit"), now: now) == .corrected("git commit"))
    }

    @Test("Past capacity the oldest verdict is dropped and the newest is kept.")
    func evictsTheOldest() {
        var cache = VerdictCache()
        for index in 0...VerdictCache.capacity {
            cache.remember(.attested, for: key("candidate \(index)"), now: .now)
        }
        #expect(cache.count == VerdictCache.capacity)
        #expect(cache.verdict(for: key("candidate 0"), now: .now) == nil)
        #expect(cache.verdict(for: key("candidate \(VerdictCache.capacity)"), now: .now) == .attested)
    }

    @Test("Forgetting everything leaves nothing behind.")
    func forgets() {
        var cache = VerdictCache()
        let now = ContinuousClock.now
        cache.remember(.attested, for: key("git commit"), now: now)
        cache.forgetEverything()
        #expect(cache.count == 0)
        #expect(cache.verdict(for: key("git commit"), now: now) == nil)
    }
}
