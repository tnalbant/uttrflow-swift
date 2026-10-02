// Tests that a notice closes the panel only when nothing is done in it meanwhile.

import Foundation
import Testing
import UttrflowTestSupport

@testable import Uttrflow

@MainActor
@Suite("Closing the panel after a notice")
struct NoticeLingerTests {
    @Test("with no further input the panel closes after the linger")
    func closesWhenLeftAlone() async throws {
        let linger = NoticeLinger(linger: .milliseconds(20))
        var closed = false
        linger.start { closed = true }
        try await eventually { closed && !linger.isPending }
        #expect(closed)
        #expect(!linger.isPending)
    }

    @Test("a key pressed within the linger keeps the panel open past it")
    func aKeyKeepsItOpen() async throws {
        let sleep = SuspendedSleep()
        let linger = NoticeLinger(linger: .milliseconds(50)) { _ in await sleep.wait() }
        var closed = false
        linger.start { closed = true }
        await sleep.waitUntilSleeping()
        linger.interrupt()
        await sleep.release()
        await sleep.waitUntilReturned()
        #expect(!closed)
    }

    @Test("a second notice restarts the wait rather than closing twice")
    func aSecondNoticeRestarts() async throws {
        let linger = NoticeLinger(linger: .milliseconds(20))
        var closes = 0
        linger.start { closes += 1 }
        linger.start { closes += 1 }
        try await eventually { closes == 1 && !linger.isPending }
        #expect(closes == 1)
    }
}

private actor SuspendedSleep {
    private var continuation: CheckedContinuation<Void, Never>?
    private var sleeping: [CheckedContinuation<Void, Never>] = []
    private var returned: [CheckedContinuation<Void, Never>] = []
    private var hasReturned = false

    func wait() async {
        for waiter in sleeping { waiter.resume() }
        sleeping.removeAll()
        await withCheckedContinuation { continuation = $0 }
        hasReturned = true
        for waiter in returned { waiter.resume() }
        returned.removeAll()
    }

    func waitUntilSleeping() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { sleeping.append($0) }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }

    func waitUntilReturned() async {
        guard !hasReturned else { return }
        await withCheckedContinuation { returned.append($0) }
    }
}
