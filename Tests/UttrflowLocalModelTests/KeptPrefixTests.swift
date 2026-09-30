import Testing

@testable import UttrflowLocalModel

private actor PassWaitGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var waitingContinuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation {
            continuation = $0
            waitingContinuation?.resume()
            waitingContinuation = nil
        }
    }

    func waitUntilBlocked() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { waitingContinuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@Suite("Reading the last pass's prompt again as far as the two share")
struct KeptPrefixTests {
    /// How many opening tokens the warm instructions already hold, which reuse has to beat to be worth anything.
    private let warmed = 4

    @Test("A pass cancelled while waiting restores its taken prefix for the next changed tail.")
    func cancelledWaitRestoresTakenPrefix() async {
        let previous = MLXCandidateScorer.KeptPrefix(tokens: [1, 2, 3, 4, 5, 6, 7], cache: "cache")
        let gate = PassWaitGate()
        let waitingPass = Task {
            do {
                await gate.wait()
                try Task.checkCancellation()
                return Optional<MLXCandidateScorer.KeptPrefix<String>>.none
            } catch {
                return MLXCandidateScorer.restoring(current: nil, taken: previous, weightsLoaded: true)
            }
        }
        await gate.waitUntilBlocked()
        waitingPass.cancel()
        await gate.release()
        let restored = await waitingPass.value

        #expect(restored?.tokens == previous.tokens)
        #expect(restored?.cache == "cache")
        let nextPrompt = [1, 2, 3, 4, 5, 6, 8]
        let shared = MLXCandidateScorer.sharedPrefix(
            of: restored?.tokens ?? [], and: nextPrompt, beating: warmed)
        #expect(shared == 6)
        #expect(nextPrompt.count - (shared ?? 0) == 1)
    }

    @Test("A failed pass never replaces a newer prefix or restores after the weights unload.")
    func restorationPreservesNewerStateAndLoadedBoundary() {
        let old = MLXCandidateScorer.KeptPrefix(tokens: [1, 2, 3], cache: "old")
        let newer = MLXCandidateScorer.KeptPrefix(tokens: [4, 5, 6], cache: "newer")

        #expect(
            MLXCandidateScorer.restoring(current: newer, taken: old, weightsLoaded: true)?.cache == "newer")
        #expect(
            MLXCandidateScorer.restoring(
                current: Optional<MLXCandidateScorer.KeptPrefix<String>>.none,
                taken: old, weightsLoaded: false) == nil)
    }

    @Test("Consecutive keystrokes share every token but the ones the typed line added.")
    func aKeystrokeSharesAllButItsOwnTokens() {
        let read = [1, 2, 3, 4, 5, 6, 7, 8]
        let all = [1, 2, 3, 4, 5, 6, 7, 9, 10]
        #expect(MLXCandidateScorer.sharedPrefix(of: read, and: all, beating: warmed) == 7)
    }

    @Test("A prompt sharing no more than the warmed instructions is read from those instead.")
    func sharingOnlyTheInstructionsIsNoReuse() {
        let read = [1, 2, 3, 4, 5, 6]
        #expect(MLXCandidateScorer.sharedPrefix(of: read, and: [1, 2, 3, 4, 7], beating: warmed) == nil)
        #expect(MLXCandidateScorer.sharedPrefix(of: read, and: [1, 2, 3, 9], beating: warmed) == nil)
        #expect(MLXCandidateScorer.sharedPrefix(of: [], and: [1, 2, 3, 4, 5, 6], beating: 0) == nil)
        #expect(MLXCandidateScorer.sharedPrefix(of: read, and: [], beating: 0) == nil)
    }

    @Test(
        "A prompt the cache already holds whole keeps its last token back, since the model answers from it.")
    func theLastTokenIsAlwaysRead() {
        let read = [1, 2, 3, 4, 5, 6, 7]
        #expect(MLXCandidateScorer.sharedPrefix(of: read, and: read, beating: warmed) == 6)
        #expect(MLXCandidateScorer.sharedPrefix(of: read + [8], and: read, beating: warmed) == 6)
        #expect(
            MLXCandidateScorer.sharedPrefix(of: [1, 2, 3, 4, 5], and: [1, 2, 3, 4, 5], beating: warmed) == nil
        )
    }

    @Test("A token that changed inside the shared run ends it, however much matches after.")
    func aChangeInsideTheRunEndsIt() {
        let read = [1, 2, 3, 4, 5, 6, 7, 8]
        #expect(MLXCandidateScorer.sharedPrefix(of: read, and: [1, 2, 3, 4, 9, 6, 7, 8], beating: 3) == 4)
        #expect(
            MLXCandidateScorer.sharedPrefix(of: read, and: [1, 2, 3, 4, 9, 6, 7, 8], beating: warmed) == nil)
    }
}
