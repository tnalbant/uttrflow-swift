// Tests for the shared scripting every fake answers through: runs of outcomes, call durations and the clock.

import Testing

@testable import UttrflowCore
@testable import UttrflowTestSupport

@Suite("Scripted fakes", .timeLimit(.minutes(1)))
struct ScriptedFakesTests {
    @Test("a sequence answers in order and repeats its last outcome once spent")
    func sequenceRepeatsItsLast() throws {
        var outcomes = ScriptedSequence<Int, SpeechEngineError>.successes([1, 2], afterwards: .failure(.nothingHeard))

        #expect(try outcomes.next().resolve() == 1)
        #expect(try outcomes.next().resolve() == 2)
        #expect(throws: SpeechEngineError.nothingHeard) { try outcomes.next().resolve() }
        #expect(throws: SpeechEngineError.nothingHeard) { try outcomes.next().resolve() }
    }

    @Test("a sequence of successes alone repeats the last success")
    func successesRepeatTheLast() throws {
        var outcomes = ScriptedSequence<Int, SpeechEngineError>.successes([1, 2])
        _ = outcomes.next()

        #expect(try outcomes.next().resolve() == 2)
        #expect(try outcomes.next().resolve() == 2)
    }

    @Test("a speech engine reads its script call by call and charges the clock for each")
    func speechEngineFollowsItsScript() async throws {
        let clock = ManualClock()
        let engine = FakeSpeechEngine(
            transcribing: .successes([.fixture(text: "one"), .fixture(text: "two")]),
            takes: .charged(.milliseconds(300), to: clock))

        let first = try await engine.transcribe(.silence(seconds: 1), options: TranscriptionOptions())
        let second = try await engine.transcribe(.silence(seconds: 1), options: TranscriptionOptions())

        #expect([first.text, second.text] == ["one", "two"])
        #expect(clock.now.offset == .milliseconds(600))
    }

    @Test("a call slept on a clock returns only once the clock reaches it")
    func sleptCallWaitsForTheClock() async throws {
        let clock = ManualClock()
        let inserter = FakeTextInserter(takes: .slept(.seconds(2), on: clock))
        let inserting = Task { try await inserter.insert("words") }

        await clock.advanceWhenSomethingIsWaiting(by: .seconds(2))

        #expect(try await inserting.value.method == .accessibility)
        #expect(inserter.received == ["words"])
    }

    @Test("a cleaner answers its scripted run in order and records every request")
    func cleanerFollowsItsScript() async throws {
        let cleaner = FakeTranscriptCleaner(
            answering: ScriptedSequence(
                .success(TransformationResult(text: "Tidied.", producedBy: .foundationModels)),
                then: [.failure(.noCapableTransformer)]))

        #expect(try await cleaner.clean(.fixture()).text == "Tidied.")
        await #expect(throws: TransformationError.noCapableTransformer) { try await cleaner.clean(.fixture()) }
        #expect(cleaner.requests.count == 2)
    }

    @Test("a cleaner that tidies passes the words through its rule")
    func cleanerTidiesTheWords() async throws {
        let cleaner = FakeTranscriptCleaner(tidying: { $0.uppercased() })

        #expect(try await cleaner.clean(.fixture(transcription: .fixture(text: "ship it"))).text == "SHIP IT")
    }

    @Test("a clock that advances when slept moves to the deadline and returns at once")
    func advancesWhenSlept() async throws {
        let clock = ManualClock(advancesWhenSlept: true)

        try await clock.sleep(for: .milliseconds(40))
        try await clock.sleep(until: ManualClock.Instant(offset: .milliseconds(10)), tolerance: nil)

        #expect(clock.now.offset == .milliseconds(40), "a deadline already passed leaves the clock where it is")
    }
}
