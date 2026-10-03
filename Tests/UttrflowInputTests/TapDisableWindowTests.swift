import Dispatch
import Synchronization
import Testing
import UttrflowTestSupport

@testable import UttrflowInput

@Suite("Re-enabling a tap the system keeps disabling")
struct TapDisableWindowTests {
    /// One second in the uptime nanoseconds the window is measured in.
    private let second: UInt64 = 1_000_000_000

    @Test("The first disable is always re-enabled.")
    func firstIsReEnabled() {
        let result = TapDisableWindow.decide(last: 0, now: 5 * second, count: 0)
        #expect(result.reEnable)
        #expect(result.count == 1)
    }

    @Test("Two disables close together give up, so a genuine fault does not loop forever.")
    func twoCloseTogetherGiveUp() {
        let first = TapDisableWindow.decide(last: 0, now: 10 * second, count: 0)
        let next = TapDisableWindow.decide(
            last: 10 * second, now: 11 * second, count: first.count)
        #expect(!next.reEnable)
    }

    @Test("Two disables far apart both re-enable, so sleep and wake do not add up to a fault.")
    func twoFarApartBothReEnable() {
        let first = TapDisableWindow.decide(last: 0, now: 10 * second, count: 0)
        // A day later: outside the window, so the count restarts and the tap comes back.
        let later = 10 * second + 86_400 * second
        let next = TapDisableWindow.decide(last: 10 * second, now: later, count: first.count)
        #expect(next.reEnable)
        #expect(next.count == 1)
    }
}

@Suite("Delivery telling its give-up handler")
struct DeliveryGaveUpTests {
    @Test("the give-up handler is not told on the first disable, only once the tap is left off")
    func toldOnlyOnceTheTapIsLeftOff() {
        let delivery = Delivery()
        let gaveUp = Mutex(false)
        delivery.setGaveUpHandler { gaveUp.withLock { $0 = true } }

        #expect(delivery.shouldReEnable())
        #expect(!gaveUp.withLock { $0 })

        // Immediately after, so it reads as the same fault and the window's limit is reached.
        #expect(!delivery.shouldReEnable())
        #expect(gaveUp.withLock { $0 })
    }

    @Test("disables a window apart on the delivery's clock both re-enable, and closer ones give up")
    func measuredOnTheInjectedClock() {
        let clock = ManualClock()
        let delivery = Delivery(clock: clock)
        #expect(delivery.shouldReEnable())
        clock.advance(by: .nanoseconds(Int64(TapDisableWindow.windowNanoseconds)))
        #expect(delivery.shouldReEnable())
        clock.advance(by: .nanoseconds(Int64(TapDisableWindow.windowNanoseconds) - 1))
        #expect(!delivery.shouldReEnable())
    }

    @Test("the interceptor's tap state measures its disables on the clock it is given")
    func tapStateMeasuredOnTheInjectedClock() {
        let clock = ManualClock()
        let source = DispatchSource.makeUserDataAddSource(queue: DispatchQueue(label: "test.tap-clock"))
        source.resume()
        let state = TapState(signal: source, clock: clock)
        #expect(state.shouldReEnable())
        clock.advance(by: .nanoseconds(Int64(TapDisableWindow.windowNanoseconds)))
        #expect(state.shouldReEnable())
        #expect(!state.shouldReEnable())
    }
}
