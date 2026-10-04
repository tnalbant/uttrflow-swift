// Tests that a clipboard read another process has to answer cannot hold up the watcher (#895).

import Foundation
import Testing
import UttrflowCore

@testable import UttrflowClipboard

/// A source whose `text()` takes longer than the limit, standing in for a promised or remote copy.
private final class SlowSource: ClipboardSource, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 1
    private var isSlow = true

    func changeCount() -> Int { lock.withLock { count } }
    func bumpChangeCount() { lock.withLock { count += 1 } }
    func deliverPromptly() { lock.withLock { isSlow = false } }

    func text() -> String? {
        if lock.withLock({ isSlow }) {
            Thread.sleep(forTimeInterval: 5)
        }
        return "delivered at last"
    }

    func html() -> String? { nil }
    func markers() -> PasteboardMarkers { PasteboardMarkers() }
    func image() -> (data: Data, width: Int, height: Int)? { nil }
    func frontmostApplicationName() -> String? { nil }
}

@Suite("A clipboard read the writing app has not answered", .serialized)
struct SlowClipboardReadTests {
    @Test("the read is given up on, and the next copy is still noticed")
    func aSlowReadIsGivenUpOn() async {
        let source = SlowSource()
        let watcher = PasteboardWatcher(
            source: source, interval: .milliseconds(10), readLimit: .milliseconds(200))
        source.bumpChangeCount()

        // The answer is what is checked, not the clock: a loaded machine can be slow to resume either way.
        let clip = await watcher.newClip(at: Date())

        #expect(clip == nil, "a copy nobody delivered in time is skipped")

        source.deliverPromptly()
        source.bumpChangeCount()
        #expect(await watcher.newClip(at: Date())?.clip.text == "delivered at last")
    }

    @Test("outstanding workers are bounded across timed-out copies, and a later healthy copy still lands")
    func outstandingWorkersAreBounded() async {
        let source = BlockedSource()
        let watcher = PasteboardWatcher(
            source: source, interval: .milliseconds(10), readLimit: .milliseconds(50))

        // Every one of these copies blocks in `text()` and times out from the caller's side.
        for _ in 0..<(PasteboardWatcher.maxOutstandingReads + 3) {
            source.bumpChangeCount()
            let clip = await watcher.newClip(at: Date())
            #expect(clip == nil)
        }
        #expect(await watcher.outstandingReads == PasteboardWatcher.maxOutstandingReads)

        // Freeing the blocked workers lets them return and give their slots back.
        source.releaseBlocked()
        while await watcher.outstandingReads != 0 { await Task.yield() }

        source.deliverPromptly()
        source.bumpChangeCount()
        #expect(await watcher.newClip(at: Date())?.clip.text == "delivered at last")
    }
}

/// A source whose `text()` blocks until released, so a caller can hold several readers open at once.
private final class BlockedSource: ClipboardSource, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 1
    private var isBlocked = true
    private let gate = DispatchSemaphore(value: 0)

    func changeCount() -> Int { lock.withLock { count } }
    func bumpChangeCount() { lock.withLock { count += 1 } }
    func deliverPromptly() { lock.withLock { isBlocked = false } }
    /// Lets every reader parked in `text()` return.
    func releaseBlocked() { gate.signal() }

    func text() -> String? {
        if lock.withLock({ isBlocked }) {
            gate.wait()
            gate.signal()
        }
        return "delivered at last"
    }

    func html() -> String? { nil }
    func markers() -> PasteboardMarkers { PasteboardMarkers() }
    func image() -> (data: Data, width: Int, height: Int)? { nil }
    func frontmostApplicationName() -> String? { nil }
}
