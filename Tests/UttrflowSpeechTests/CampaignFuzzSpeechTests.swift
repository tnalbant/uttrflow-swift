// Campaign fuzz: RecogniserTurn and BackedSpeechEngine storms, prompt row shifting, allowed-language sampling. Not for commit.
import CoreML
import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowSpeech

private struct CampaignRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private final class Occupancy: Sendable {
    struct Counts {
        var inside = 0
        var most = 0
        var admitted = 0
    }
    let counts = Mutex(Counts())
    func enter() { counts.withLock { $0.inside += 1; $0.most = max($0.most, $0.inside); $0.admitted += 1 } }
    func leave() { counts.withLock { $0.inside -= 1 } }
    var most: Int { counts.withLock { $0.most } }
}

/// A backend that counts overlap across load and transcribe, yields while inside, and fails loads on demand.
private final class OverlapBackend: TranscriptionBackend {
    struct State {
        var inside = 0
        var most = 0
        var loads = 0
        var successfulLoads = 0
        var decodes = 0
        var failLoads = 0
    }
    let state = Mutex(State())
    let yields: Int

    init(yields: Int, failLoads: Int) {
        self.yields = yields
        state.withLock { $0.failLoads = failLoads }
    }

    func load() async throws(SpeechEngineError) {
        let fail = state.withLock { s -> Bool in
            s.inside += 1
            s.most = max(s.most, s.inside)
            s.loads += 1
            if s.failLoads > 0 {
                s.failLoads -= 1
                return true
            }
            s.successfulLoads += 1
            return false
        }
        for _ in 0..<yields { await Task.yield() }
        state.withLock { $0.inside -= 1 }
        if fail { throw .modelLoadFailed(description: "fuzz") }
    }

    func transcribe(
        _ samples: [Float], languageHint: LanguageCode?
    ) async throws(SpeechEngineError) -> RawTranscript {
        state.withLock { s in
            s.inside += 1
            s.most = max(s.most, s.inside)
            s.decodes += 1
        }
        for _ in 0..<yields { await Task.yield() }
        state.withLock { $0.inside -= 1 }
        return RawTranscript(text: "hello there")
    }
}

@Suite("CampaignFuzz speech", .serialized)
struct CampaignFuzzSpeechTests {
    @Test("RecogniserTurn: take/release/cancel storms admit one at a time and lose no waiter", .timeLimit(.minutes(20)))
    func turnStorm() async throws {
        var rng = CampaignRNG(state: 0x5EED_0001)
        let rounds = Int(ProcessInfo.processInfo.environment["CAMPAIGN_TURN_ROUNDS"] ?? "") ?? 400
        var totalTasks = 0
        var totalAdmitted = 0
        var totalCancelled = 0
        for round in 0..<rounds {
            let turn = RecogniserTurn()
            let occupancy = Occupancy()
            let count = Int.random(in: 2...96, using: &rng)
            let plans: [(cancelAfter: Int?, hold: Int)] = (0..<count).map { _ in
                (
                    Bool.random(using: &rng) ? Int.random(in: 0...30, using: &rng) : nil,
                    Int.random(in: 0...6, using: &rng)
                )
            }
            let tasks = plans.map { plan in
                Task { () -> Bool in
                    do { try await turn.take() } catch { return false }
                    occupancy.enter()
                    for _ in 0..<plan.hold { await Task.yield() }
                    occupancy.leave()
                    turn.release()
                    return true
                }
            }
            await withTaskGroup(of: Void.self) { group in
                for (index, plan) in plans.enumerated() {
                    guard let after = plan.cancelAfter else { continue }
                    group.addTask {
                        for _ in 0..<after { await Task.yield() }
                        tasks[index].cancel()
                    }
                }
            }
            for (index, task) in tasks.enumerated() {
                let admitted = await task.value
                if admitted {
                    totalAdmitted += 1
                } else {
                    totalCancelled += 1
                    #expect(plans[index].cancelAfter != nil, "round \(round): waiter \(index) refused without cancel")
                }
            }
            totalTasks += count
            #expect(occupancy.most <= 1, "round \(round): \(occupancy.most) holders at once")
            // The turn is free afterwards: a fresh take is admitted.
            try await turn.take()
            turn.release()
        }
        print(
            "CAMPAIGN turnStorm rounds=\(rounds) tasks=\(totalTasks) admitted=\(totalAdmitted) cancelled=\(totalCancelled)"
        )
    }

    @Test("RecogniserTurn: thread-pool hammer with blocking holders", .timeLimit(.minutes(10)))
    func turnThreadHammer() async throws {
        let turn = RecogniserTurn()
        let occupancy = Occupancy()
        let iterations = 20_000
        await withTaskGroup(of: Void.self) { group in
            for worker in 0..<32 {
                group.addTask {
                    for step in 0..<(iterations / 32) {
                        let inner = Task {
                            try await turn.take()
                            occupancy.enter()
                            if step % 7 == 0 { usleep(10) }
                            occupancy.leave()
                            turn.release()
                        }
                        if (worker + step) % 5 == 0 { inner.cancel() }
                        _ = await inner.result
                    }
                }
            }
        }
        #expect(occupancy.most <= 1)
        try await turn.take()
        turn.release()
        print("CAMPAIGN turnThreadHammer iterations=\(iterations) admitted=\(occupancy.counts.withLock { $0.admitted })")
    }

    @Test("BackedSpeechEngine: prepare/transcribe/cancel storms never overlap the backend and load once", .timeLimit(.minutes(20)))
    func engineStorm() async throws {
        var rng = CampaignRNG(state: 0x5EED_0002)
        let speech = AudioSamples.canonical(Array(repeating: 0.1, count: AudioSamples.canonicalSampleRate))
        let rounds = 150
        var calls = 0
        for round in 0..<rounds {
            let failLoads = Int.random(in: 0...2, using: &rng)
            let backend = OverlapBackend(yields: Int.random(in: 0...8, using: &rng), failLoads: failLoads)
            let engine = BackedSpeechEngine(kind: .whisperKit, backend: backend)
            let count = Int.random(in: 1...40, using: &rng)
            var tasks: [Task<Void, any Error>] = []
            var cancels: [Int?] = []
            for _ in 0..<count {
                if Bool.random(using: &rng) {
                    tasks.append(Task { try await engine.prepare() })
                } else {
                    tasks.append(Task { _ = try await engine.transcribe(speech, options: .automatic) })
                }
                cancels.append(Int.random(in: 0...3, using: &rng) == 0 ? Int.random(in: 0...20, using: &rng) : nil)
            }
            let started = tasks
            await withTaskGroup(of: Void.self) { group in
                for (index, after) in cancels.enumerated() {
                    guard let after else { continue }
                    group.addTask {
                        for _ in 0..<after { await Task.yield() }
                        started[index].cancel()
                    }
                }
            }
            for task in started { _ = await task.result }
            calls += count
            let state = backend.state.withLock { $0 }
            #expect(state.most <= 1, "round \(round): backend overlap \(state.most)")
            #expect(state.successfulLoads <= 1, "round \(round): loaded \(state.successfulLoads) times")
            // After the storm the engine still works.
            _ = try? await engine.transcribe(speech, options: .automatic)
            let after = backend.state.withLock { $0 }
            #expect(after.successfulLoads == 1 || after.loads > state.loads, "round \(round): engine stuck")
        }
        print("CAMPAIGN engineStorm rounds=\(rounds) calls=\(calls)")
    }

    @Test("PromptAlignedSegmentSeeker.rows over random shapes, types and offsets")
    func rowsFuzz() throws {
        var rng = CampaignRNG(state: 0x5EED_0003)
        let types: [MLMultiArrayDataType] = [.float32, .float16, .double, .int32]
        var checked = 0
        for _ in 0..<20_000 {
            let rank = Int.random(in: 1...3, using: &rng)
            let shape = (0..<rank).map { _ in NSNumber(value: Int.random(in: 1...40, using: &rng)) }
            let type = types.randomElement(using: &rng)!
            let weights = try MLMultiArray(shape: shape, dataType: type)
            weights.withUnsafeMutableBytes { bytes, _ in
                for index in 0..<bytes.count { bytes[index] = UInt8(truncatingIfNeeded: rng.next()) }
            }
            let first: Int
            switch Int.random(in: 0...5, using: &rng) {
            case 0: first = Int.random(in: Int.min...0, using: &rng)
            case 1: first = Int.random(in: 1_000...Int.max, using: &rng)
            default: first = Int.random(in: 0...45, using: &rng)
            }
            let shifted = try PromptAlignedSegmentSeeker.rows(of: weights, from: first)
            #expect(shifted.shape == weights.shape)
            #expect(shifted.dataType == weights.dataType)
            guard first > 0, rank == 2 else {
                #expect(shifted === weights)
                continue
            }
            let rows = shape[0].intValue
            let source = weights.withUnsafeBytes { Array($0.bindMemory(to: UInt8.self)) }
            let result = shifted.withUnsafeBytes { Array($0.bindMemory(to: UInt8.self)) }
            let rowBytes = source.count / rows
            for row in 0..<rows {
                let got = result[(row * rowBytes)..<((row + 1) * rowBytes)]
                if row + first < rows {
                    let want = source[((row + first) * rowBytes)..<((row + first + 1) * rowBytes)]
                    #expect(Array(got) == Array(want))
                } else {
                    #expect(got.allSatisfy { $0 == 0 })
                }
            }
            checked += 1
        }
        print("CAMPAIGN rowsFuzz iterations=20000 shiftedChecked=\(checked)")
    }

    @Test("AllowedLanguageSampler over hostile logits")
    func samplerFuzz() async throws {
        var rng = CampaignRNG(state: 0x5EED_0004)
        let specials: [Float] = [.nan, .infinity, -.infinity, .greatestFiniteMagnitude, -.greatestFiniteMagnitude, 0, -0.0, .leastNonzeroMagnitude]
        for _ in 0..<5_000 {
            let vocabulary = Int.random(in: 1...300, using: &rng)
            let logits = try MLMultiArray(shape: [1, 1, NSNumber(value: vocabulary)], dataType: .float32)
            var values: [Float] = []
            for index in 0..<vocabulary {
                let value =
                    Int.random(in: 0...9, using: &rng) == 0
                    ? specials.randomElement(using: &rng)! : Float.random(in: -1e4...1e4, using: &rng)
                values.append(value)
                logits[[0, 0, NSNumber(value: index)]] = NSNumber(value: value)
            }
            let allowed = (0..<Int.random(in: 0...6, using: &rng)).map { _ in Int.random(in: 0..<vocabulary, using: &rng) }
            let sampler = AllowedLanguageSampler(allowedTokens: allowed)
            let result = await sampler.update(tokens: [1, 2], logits: logits, logProbs: [0, 0])
            if allowed.isEmpty {
                #expect(result.completed)
                continue
            }
            #expect(result.tokens.count == 3)
            let chosen = result.tokens.last!
            #expect(allowed.contains(chosen))
            let scores = allowed.map { values[$0] }
            if !scores.contains(where: \.isNaN) {
                #expect(values[chosen] == scores.max()!)
                let soft = AllowedLanguageSampler.logSoftmax(scores)
                if scores.allSatisfy(\.isFinite) {
                    #expect(soft.allSatisfy { $0 <= 1e-3 && !$0.isNaN })
                }
            }
        }
        print("CAMPAIGN samplerFuzz iterations=5000")
    }
}
