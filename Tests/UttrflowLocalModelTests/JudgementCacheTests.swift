import Foundation
import Testing

@testable import UttrflowLocalModel

/// The cache that holds a candidate's per-token log-softmax rows, so a keystroke after the first is read from memory.
@Suite("MLX candidate scorer judgement cache")
struct JudgementCacheTests {
    @Test("A candidate remembered once is read back unchanged.")
    func roundTripsTheLine() {
        var cache = JudgementCache()
        let line = JudgedLine(tokens: [1, 2, 3], rows: [[0.1], [0.2], [0.3]], texts: ["a", "b", "c"])
        cache.remember(line, for: "please")
        #expect(cache.recall(candidate: "please") == line)
    }

    @Test("A candidate never remembered reads as nothing.")
    func anUnseenCandidateMisses() {
        let cache = JudgementCache()
        #expect(cache.recall(candidate: "never scored") == nil)
    }

    @Test("Re-remembering a candidate does not grow the cache or change the order.")
    func reRememberingDoesNotGrow() {
        var cache = JudgementCache()
        let first = JudgedLine(tokens: [1], rows: [[0.1]], texts: ["a"])
        let second = JudgedLine(tokens: [2], rows: [[0.2]], texts: ["b"])
        cache.remember(first, for: "alpha")
        cache.remember(second, for: "alpha")
        #expect(cache.count == 1)
        #expect(cache.recall(candidate: "alpha") == second)
    }

    @Test("Capacity drops the oldest candidate, never the most recent.")
    func capacityEvictsTheOldest() {
        var cache = JudgementCache()
        for index in 0..<(JudgementCache.capacity + 3) {
            let line = JudgedLine(
                tokens: [index], rows: [[Float(index)]], texts: ["\(index)"])
            cache.remember(line, for: "candidate-\(index)")
        }
        #expect(cache.count == JudgementCache.capacity)
        #expect(cache.recall(candidate: "candidate-0") == nil)
        #expect(cache.recall(candidate: "candidate-1") == nil)
        #expect(cache.recall(candidate: "candidate-3") != nil)
    }

    @Test("A hit moves a candidate to the most-recent position so capacity drops the next-oldest one.")
    func recallMovesToMostRecent() {
        var cache = JudgementCache()
        for index in 0..<JudgementCache.capacity {
            let line = JudgedLine(
                tokens: [index], rows: [[Float(index)]], texts: ["\(index)"])
            cache.remember(line, for: "candidate-\(index)")
        }
        _ = cache.recall(candidate: "candidate-0")
        let overflow = JudgedLine(
            tokens: [99], rows: [[99.0]], texts: ["99"])
        cache.remember(overflow, for: "candidate-new")
        #expect(cache.recall(candidate: "candidate-0") != nil)
        #expect(cache.recall(candidate: "candidate-1") == nil)
    }

    @Test("Forget everything empties the cache, so the next recall misses.")
    func forgetEverythingClears() {
        var cache = JudgementCache()
        cache.remember(JudgedLine(tokens: [1], rows: [[0.1]], texts: ["a"]), for: "alpha")
        cache.forgetEverything()
        #expect(cache.count == 0)
        #expect(cache.recall(candidate: "alpha") == nil)
    }
}

/// A vocabulary the `bytes` table can look bytes up in, used by `JudgedLine.judged`. Token 0 is BOS, 1 is "p", 2 is "pl", 3 is "ple", 4 is "lease".
private let scorerBytes: [[UInt8]] = [
    "<bos>", "p", "pl", "ple", "lease", " ", "send", " the", " report",
].map { Array($0.utf8) }

@Suite("A cached line answers each new typed prefix from the same rows")
struct JudgedLineTests {
    @Test("A typed prefix that ends on a token boundary is read straight from the cache.")
    func typedOnBoundaryReturnsCachedTokens() {
        let tokens = [0, 2, 3, 4, 5, 6, 7]
        let vocab = scorerBytes.count
        let row = [Float](repeating: -10, count: vocab)
        let rows = Array(repeating: row, count: tokens.count)
        let texts = tokens.map { _ in "x" }
        let line = JudgedLine(tokens: tokens, rows: rows, texts: texts)
        let typed = [0, 2]
        let judged = JudgedLine.judged(from: line, typedTokens: typed, bytes: scorerBytes)
        #expect(judged.count == tokens.count - 2)
    }

    @Test("A typed prefix that ends mid-token returns the slice from the cached rows.")
    func typedMidTokenReturnsTheSlice() {
        let tokens = [0, 3, 4, 5, 6, 7]
        let vocab = scorerBytes.count
        let row = [Float](repeating: -10, count: vocab)
        let rows = Array(repeating: row, count: tokens.count)
        let texts = tokens.map { _ in "x" }
        let line = JudgedLine(tokens: tokens, rows: rows, texts: texts)
        let typed = [0, 1]
        let judged = JudgedLine.judged(from: line, typedTokens: typed, bytes: scorerBytes)
        #expect(judged.count == tokens.count - 1)
    }

    @Test("An empty cached line returns nothing rather than indexing out of bounds.")
    func emptyLineReturnsNothing() {
        let line = JudgedLine(tokens: [], rows: [], texts: [])
        #expect(JudgedLine.judged(from: line, typedTokens: [], bytes: []) == [])
    }

    @Test("A typed prefix whose tokens diverge inside the cached start reads the same scored span.")
    func retokenisedJoinReadsSameSpan() {
        // Cached line: bos, "pl", "ple", "lease", " ", "send", " the".
        let tokens = [0, 2, 3, 4, 5, 6, 7]
        let vocab = scorerBytes.count
        let row = [Float](repeating: -10, count: vocab)
        let rows = Array(repeating: row, count: tokens.count)
        let texts = tokens.map { _ in "x" }
        let line = JudgedLine(tokens: tokens, rows: rows, texts: texts)
        let onBoundary = JudgedLine.judged(from: line, typedTokens: [0, 2], bytes: scorerBytes)
        let retokenised = JudgedLine.judged(from: line, typedTokens: [0, 3], bytes: scorerBytes)
        #expect(retokenised.count == onBoundary.count)
    }
}
