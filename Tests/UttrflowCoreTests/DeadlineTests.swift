import Testing

import UttrflowCore
@testable import UttrflowTestSupport

@Suite("Holding a read to a time")
struct DeadlineTests {
    @Test("An answer that arrives in time is the answer.")
    func promptAnswersAreKept() async {
        let answer = await withDeadline(.milliseconds(500)) { "here" }
        #expect(answer == "here")
    }

    @Test("An answer that does not arrive in time is nothing, and the race did not wait for it.")
    func lateAnswersAreNothing() async {
        let clock = ManualClock()
        let witness = Witness()
        let racing = Task {
            await withDeadline(.milliseconds(50), clock: clock) { () async -> String? in
                try? await clock.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return nil }
                await witness.finished()
                return "late"
            }
        }
        while !clock.advanceIfSomethingIsWaiting(exactly: .milliseconds(50)) { await Task.yield() }
        let answer = await racing.value
        #expect(answer == nil)
        #expect(await witness.didFinish == false)
    }

    @Test("Work that answers nothing is nothing, promptly.")
    func nothingIsNothing() async {
        let answer: String? = await withDeadline(.milliseconds(500)) { nil }
        #expect(answer == nil)
    }

    @Test("An answer that takes a while but arrives inside the allowance is still the answer.")
    func slowButTimelyAnswersAreKept() async {
        let clock = ManualClock()
        let racing = Task {
            await withDeadline(.milliseconds(800), clock: clock) { () async -> String? in
                try? await clock.sleep(for: .milliseconds(20))
                return "here"
            }
        }
        while !clock.advanceIfSomethingIsWaiting(exactly: .milliseconds(20)) { await Task.yield() }
        let answer = await racing.value
        #expect(answer == "here")
    }

    @Test(
        "The race is over when the allowance is, however long the work would take: the loser has not finished when the caller has its answer.",
        arguments: [1, 10, 40, 80])
    func theRaceEndsOnTime(allowance: Int) async {
        let clock = ManualClock()
        let witness = Witness()
        let racing = Task {
            await withDeadline(.milliseconds(allowance), clock: clock) { () async -> String? in
                try? await clock.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return nil }
                await witness.finished()
                return "late"
            }
        }
        let duration = Duration.milliseconds(allowance)
        while !clock.advanceIfSomethingIsWaiting(exactly: duration) { await Task.yield() }
        let answer = await racing.value
        #expect(answer == nil)
        // Judged by the loser's own state rather than a clock, since a loaded test run has been seen to stall the process for ten seconds.
        #expect(await witness.didFinish == false)
    }

    @Test("Work that cannot be stopped is left to finish on its own rather than waited for.")
    func unstoppableWorkIsLeftBehind() async {
        let clock = ManualClock()
        let gate = UnstoppableGate()
        let witness = Witness()
        let racing = Task {
            await withDeadline(.milliseconds(40), clock: clock) { () async -> String? in
                await withCheckedContinuation { continuation in
                    Task.detached {
                        await gate.wait()
                        await witness.finished()
                        continuation.resume(returning: "late")
                    }
                }
            }
        }
        while !clock.advanceIfSomethingIsWaiting(exactly: .milliseconds(40)) { await Task.yield() }
        let answer = await racing.value
        #expect(answer == nil)
        #expect(await witness.didFinish == false)
        await gate.open()
        while !(await witness.didFinish) { await Task.yield() }
    }

    @Test(
        "The loser is cancelled: its sleep is cut short, it finds itself cancelled, and what follows the check never runs."
    )
    func theLoserIsCancelled() async {
        let clock = ManualClock()
        let witness = Witness()
        let racing = Task {
            await withDeadline(.milliseconds(30), clock: clock) { () async -> String? in
                try? await clock.sleep(for: .seconds(30))
                await witness.woke(cancelled: Task.isCancelled)
                guard !Task.isCancelled else { return nil }
                await witness.finished()
                return "late"
            }
        }
        while !clock.advanceIfSomethingIsWaiting(exactly: .milliseconds(30)) { await Task.yield() }
        let answer = await racing.value
        #expect(answer == nil)
        #expect(await witness.wakes() == true)
        #expect(await witness.didFinish == false)
    }
}

private actor UnstoppableGate {
    private var released = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        released = true
        for continuation in waiting { continuation.resume() }
        waiting.removeAll()
    }
}

/// What the losing work saw when it woke and whether it ever finished, reported from outside the race.
private actor Witness {
    var cancelledWhenWoken: Bool?
    var didFinish = false
    private var waitingToWake: [CheckedContinuation<Bool, Never>] = []

    func woke(cancelled: Bool) {
        cancelledWhenWoken = cancelled
        for waiting in waitingToWake { waiting.resume(returning: cancelled) }
        waitingToWake = []
    }

    func finished() { didFinish = true }

    /// Suspends until the losing work wakes, and answers whether it found itself cancelled.
    func wakes() async -> Bool {
        if let cancelledWhenWoken { return cancelledWhenWoken }
        return await withCheckedContinuation { waitingToWake.append($0) }
    }
}

@Suite("A deadline on an injected clock")
struct DeadlineValueTests {
    @Test("Time left falls only as the injected clock moves, and the deadline is spent when it reaches zero.")
    func remainingFollowsTheClock() async {
        let clock = ManualClock()
        let deadline = Deadline(.milliseconds(100), clock: clock)
        #expect(deadline.remaining == .milliseconds(100))
        #expect(!deadline.isSpent)
        clock.advance(by: .milliseconds(60))
        #expect(deadline.remaining == .milliseconds(40))
        clock.advance(by: .milliseconds(60))
        #expect(deadline.remaining == .zero)
        #expect(deadline.isSpent)
    }

    @Test("A race run after part of the allowance has gone gets only what is left.")
    func raceUsesWhatIsLeft() async throws {
        let clock = ManualClock()
        let deadline = Deadline(.milliseconds(100), clock: clock)
        clock.advance(by: .milliseconds(70))
        let racing = Task {
            try await deadline.race { () async throws -> String in
                try await clock.sleep(for: .seconds(30))
                return "late"
            }
        }
        while !clock.advanceIfSomethingIsWaiting(exactly: .milliseconds(30)) { await Task.yield() }
        #expect(try await racing.value == nil)
    }
}
