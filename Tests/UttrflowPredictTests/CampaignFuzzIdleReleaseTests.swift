// Campaign fuzz: IdleReleasingModel release/reload races with passes in flight. Not for commit.
import Foundation
import Synchronization
import Testing

@testable import UttrflowPredict

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

/// A model that yields inside every load and release, fails loads on a seeded coin, and counts misuse.
private actor CountingModel: ReleasableModel {
    private(set) var isLoaded = false
    private(set) var inside = 0
    private(set) var mostInside = 0
    private(set) var loads = 0
    private(set) var releases = 0
    private(set) var passesOnUnloaded = 0
    private(set) var passes = 0
    private var rng: CampaignRNG
    private let failEvery: Int
    private let yields: Int
    /// A gate the deterministic test uses to hold the first load.
    private var gate: CheckedContinuation<Void, Never>?
    private var holdFirstLoad: Bool
    private var failFirstLoad: Bool

    init(seed: UInt64, failEvery: Int, yields: Int, holdFirstLoad: Bool = false, failFirstLoad: Bool = false) {
        rng = CampaignRNG(state: seed)
        self.failEvery = failEvery
        self.yields = yields
        self.holdFirstLoad = holdFirstLoad
        self.failFirstLoad = failFirstLoad
    }

    var isHoldingGate: Bool { gate != nil }

    func openGate() {
        gate?.resume()
        gate = nil
    }

    func prepare(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        inside += 1
        mostInside = max(mostInside, inside)
        defer { inside -= 1 }
        loads += 1
        if holdFirstLoad {
            holdFirstLoad = false
            await withCheckedContinuation { gate = $0 }
            if failFirstLoad {
                failFirstLoad = false
                throw CancellationError()
            }
        }
        for _ in 0..<yields { await Task.yield() }
        if failEvery > 0, Int.random(in: 0..<failEvery, using: &rng) == 0 { throw CancellationError() }
        isLoaded = true
        onProgress(1)
    }

    func release() async {
        inside += 1
        mostInside = max(mostInside, inside)
        defer { inside -= 1 }
        releases += 1
        for _ in 0..<yields { await Task.yield() }
        isLoaded = false
    }

    var isReady: Bool { isLoaded }

    func completions(for typed: String, in situation: GenerationSituation) async throws -> [String] {
        passes += 1
        if !isLoaded { passesOnUnloaded += 1 }
        for _ in 0..<yields { await Task.yield() }
        return [typed]
    }

    func alternatives(for typed: String, in situation: GenerationSituation, excluding leader: String) async throws -> [String] {
        passes += 1
        if !isLoaded { passesOnUnloaded += 1 }
        return []
    }

    func logLikelihood(of candidate: String, following context: String) async -> Double? {
        passes += 1
        return isLoaded ? -1 : nil
    }
}

@Suite("CampaignFuzz idle release", .serialized)
struct CampaignFuzzIdleReleaseTests {
    private let situation = GenerationSituation(application: "Notes")

    /// Waits for every chained load or release to finish.
    private func drain(_ model: IdleReleasingModel<CountingModel>) async {
        for _ in 0..<50 {
            let work = await model.pendingWork
            await work?.value
            await Task.yield()
            if await model.pendingWork == work { return }
        }
    }

    @Test("random prepare/release/query/idle schedules", .timeLimit(.minutes(20)))
    func schedules() async throws {
        var rng = CampaignRNG(state: 0x5EED_0201)
        let rounds = 1_500
        var staleHeld = 0
        var loadedAfterFinalRelease = 0
        var overlaps = 0
        var operations = 0
        var firstStale: String?
        var staleByFailure: [Int: Int] = [:]
        for round in 0..<rounds {
            let failEvery = [0, 0, 2, 4].randomElement(using: &rng)!
            let inner = CountingModel(seed: rng.next(), failEvery: failEvery, yields: Int.random(in: 0...4, using: &rng))
            let model = IdleReleasingModel(model: inner, idleAfter: .seconds(3_600))
            let count = Int.random(in: 1...30, using: &rng)
            var log: [String] = []
            var tasks: [Task<Void, Never>] = []
            for _ in 0..<count {
                let op = Int.random(in: 0...6, using: &rng)
                let awaitIt = Bool.random(using: &rng)
                let task: Task<Void, Never>
                switch op {
                case 0, 1:
                    log.append("prepare")
                    task = Task { try? await model.prepare(onProgress: { _ in }) }
                case 2:
                    log.append("release")
                    task = Task { await model.release() }
                case 3:
                    log.append("isReady")
                    task = Task { _ = await model.isReady }
                case 4:
                    log.append("pass")
                    let situation = situation
                    task = Task { _ = try? await model.completions(for: "he", in: situation) }
                case 5:
                    log.append("idle")
                    task = Task { await model.releaseIfIdle(at: .now + .seconds(7_200)) }
                default:
                    log.append("notIdle")
                    task = Task { await model.releaseIfIdle(at: .now) }
                }
                if awaitIt { await task.value } else { tasks.append(task) }
                operations += 1
            }
            for task in tasks { await task.value }
            await drain(model)
            let loaded = await inner.isLoaded
            let held = await model.holdsTheModel
            if loaded && !held {
                staleHeld += 1
                staleByFailure[failEvery, default: 0] += 1
                if firstStale == nil { firstStale = "round \(round) failEvery=\(failEvery): \(log.joined(separator: ","))" }
            }
            if await inner.mostInside > 1 { overlaps += 1 }
            await model.release()
            await drain(model)
            _ = await model.isReady
            await drain(model)
            if await inner.isLoaded { loadedAfterFinalRelease += 1 }
        }
        print(
            "CAMPAIGN idleSchedules rounds=\(rounds) ops=\(operations) staleHeld=\(staleHeld) overlaps=\(overlaps) loadedAfterFinalRelease=\(loadedAfterFinalRelease)"
        )
        print("CAMPAIGN idleSchedules staleByFailEvery=\(staleByFailure)")
        if let firstStale { print("CAMPAIGN idleSchedules firstStale \(firstStale)") }
        #expect(overlaps == 0)
        #expect(loadedAfterFinalRelease == 0)
        #expect(staleHeld == 0, "model loaded while the wrapper believes it is not held, so idle release never fires")
    }

    @Test("minimal: a failed load finishing after release and prepare clears the hold of the load that succeeds", .timeLimit(.minutes(1)))
    func staleFailureClearsHold() async throws {
        let inner = CountingModel(seed: 1, failEvery: 0, yields: 0, holdFirstLoad: true, failFirstLoad: true)
        let model = IdleReleasingModel(model: inner, idleAfter: .seconds(3_600))
        let first = Task { try await model.prepare(onProgress: { _ in }) }
        while !(await inner.isHoldingGate) { await Task.yield() }
        let releasing = Task { await model.release() }
        while await model.holdsTheModel { await Task.yield() }
        let second = Task { try await model.prepare(onProgress: { _ in }) }
        while !(await model.holdsTheModel) { await Task.yield() }
        await inner.openGate()
        _ = await first.result
        await releasing.value
        _ = await second.result
        await drain(model)
        let loaded = await inner.isLoaded
        let held = await model.holdsTheModel
        print("CAMPAIGN staleFailureClearsHold loaded=\(loaded) held=\(held)")
        #expect(loaded)
        #expect(held, "the wrapper forgot it holds a loaded model; the idle watch will never release it")
        // The idle check the watch runs cannot let it go.
        let stillHeld = await model.releaseIfIdle(at: .now + .seconds(7_200))
        await drain(model)
        print("CAMPAIGN staleFailureClearsHold idleCheckReturned=\(stillHeld) loadedAfterIdleCheck=\(await inner.isLoaded)")
        #expect(await inner.isLoaded == false, "an idle window passed and the weights stayed")
    }
}
