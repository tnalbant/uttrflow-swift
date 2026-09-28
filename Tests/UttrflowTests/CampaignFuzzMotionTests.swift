// Campaign fuzz: MotionBudget, MotionBudgetObserver and WindowAttention over every ordering and hostile geometry. Not for commit.
import AppKit
import Foundation
import Testing
import UttrflowCore

@testable import Uttrflow

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

private final class BudgetSource: @unchecked Sendable {
    private let lock = NSLock()
    private var value = MotionBudget()
    var budget: MotionBudget {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

@MainActor
@Suite("CampaignFuzz motion", .serialized)
struct CampaignFuzzMotionTests {
    private static let budgets: [MotionBudget] = [false, true].flatMap { reduce in
        [false, true].flatMap { lowPower in
            ThermalPressure.allCases.map {
                MotionBudget(reducesMotion: reduce, energy: EnergyConditions(isLowPowerMode: lowPower, thermal: $0))
            }
        }
    }

    @Test("every combination of window attention and budget")
    func truthTable() {
        var checked = 0
        for bits in 0..<64 {
            for budget in Self.budgets {
                let flags = (0..<6).map { bits & (1 << $0) != 0 }
                let attention = WindowAttention(
                    isShown: flags[0], isKey: flags[1], isApplicationActive: flags[2], isApplicationHidden: flags[3],
                    isOnScreen: flags[4], isViewVisible: flags[5], motion: budget)
                let calm = !budget.energy.isLowPowerMode && budget.energy.thermal < .serious
                let want = flags[0] && flags[1] && flags[2] && !flags[3] && flags[4] && flags[5] && !budget.reducesMotion && calm
                #expect(attention.animates == want)
                #expect(budget.workingDotsMove == !budget.reducesMotion)
                #expect(budget.dockFrameInterval == (calm ? MotionBudget.fullDockFrameInterval : MotionBudget.reducedDockFrameInterval))
                #expect(budget.dockFrameInterval > 0 && budget.dockFrameInterval.isFinite)
                checked += 1
            }
        }
        print("CAMPAIGN motionTruthTable combinations=\(checked)")
    }

    @Test("every ordering of up to seven notices, with the reading changing between them")
    func noticeOrderings() {
        var rng = CampaignRNG(state: 0x5EED_0401)
        let source = BudgetSource()
        let observer = MotionBudgetObserver(read: { source.budget })
        let notices = MotionBudget.changeNotices
        var sequences = 0
        var wrong = 0
        for length in 1...7 {
            var total = 1
            for _ in 0..<length { total *= notices.count }
            for code in 0..<total {
                var rest = code
                for _ in 0..<length {
                    let notice = notices[rest % notices.count]
                    rest /= notices.count
                    if Bool.random(using: &rng) { source.budget = Self.budgets.randomElement(using: &rng)! }
                    notice.centre.post(name: notice.name, object: nil)
                    if observer.budget != source.budget { wrong += 1 }
                }
                sequences += 1
            }
        }
        print("CAMPAIGN motionOrderings sequences=\(sequences) staleAfterNotice=\(wrong)")
        #expect(wrong == 0)
    }

    @Test("notices posted from background threads while observers come and go", .timeLimit(.minutes(5)))
    func backgroundPostsAndChurn() async {
        var rng = CampaignRNG(state: 0x5EED_0402)
        let source = BudgetSource()
        var observers: [MotionBudgetObserver] = []
        var stale = 0
        for round in 0..<400 {
            if Bool.random(using: &rng) || observers.isEmpty {
                observers.append(MotionBudgetObserver(read: { source.budget }))
            } else {
                observers.remove(at: Int.random(in: 0..<observers.count, using: &rng))
            }
            let final = Self.budgets.randomElement(using: &rng)!
            let picks = (0..<Int.random(in: 1...8, using: &rng)).map { _ in Int.random(in: 0..<3, using: &rng) }
            let intermediate = Self.budgets.randomElement(using: &rng)!
            source.budget = intermediate
            let names = MotionBudget.changeNotices.map(\.name)
            let workspace = NSWorkspace.shared.notificationCenter
            await withTaskGroup(of: Void.self) { group in
                for pick in picks {
                    let name = names[pick]
                    let centre = pick == 2 ? workspace : NotificationCenter.default
                    let unsafeCentre = centre
                    group.addTask {
                        unsafeCentre.post(name: name, object: nil)
                    }
                }
            }
            source.budget = final
            MotionBudget.changeNotices[round % 3].centre.post(name: MotionBudget.changeNotices[round % 3].name, object: nil)
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
            for observer in observers where observer.budget != final { stale += 1 }
        }
        print("CAMPAIGN motionBackground rounds=400 staleObservers=\(stale) liveObservers=\(observers.count)")
        #expect(stale == 0)
    }

    @Test("hostile geometry for the uncovered frame and display overlap")
    func geometry() {
        var rng = CampaignRNG(state: 0x5EED_0403)
        let specials: [CGFloat] = [.nan, .infinity, -.infinity, .greatestFiniteMagnitude, -.greatestFiniteMagnitude, 0, -0.0, 1e-300, -1, 1e15]
        func value() -> CGFloat {
            Int.random(in: 0...5, using: &rng) == 0 ? specials.randomElement(using: &rng)! : CGFloat.random(in: -5_000...5_000, using: &rng)
        }
        func rect() -> CGRect { CGRect(x: value(), y: value(), width: value(), height: value()) }
        var nonEmpty = 0
        for _ in 0..<500_000 {
            let size = CGSize(width: abs(value()), height: abs(value()))
            let frame = rect()
            let bounds: CGRect? = Bool.random(using: &rng) ? rect() : nil
            let part = WindowAttention.uncoveredFrame(size: size, inWindow: frame, scrollViewBounds: bounds)
            if part != .zero {
                nonEmpty += 1
                #expect(part.width > 0 && part.height > 0)
                if size.width.isFinite && size.height.isFinite {
                    #expect(part.width <= size.width + 1e-6 && part.height <= size.height + 1e-6)
                }
            }
            let displays = (0..<Int.random(in: 0...3, using: &rng)).map { _ in rect() }
            #expect(WindowAttention.isVisible(unclippedFrameOnScreen: .zero, displays: displays) == false)
            _ = WindowAttention.isVisible(unclippedFrameOnScreen: part, displays: displays)
            let flipped = WindowAttention.flipped(frame, withinHeight: value())
            _ = flipped
        }
        print("CAMPAIGN windowGeometry iterations=500000 nonEmpty=\(nonEmpty)")
    }
}
