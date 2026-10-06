internal import CoreGraphics
internal import Dispatch
internal import Synchronization
internal import UttrflowPredict

/// Everything the C callback may touch, held where a raw pointer can reach it.
final class TapState: TapPayload, @unchecked Sendable {
    /// How many taken keystrokes may wait for the drain; while it is that far behind, newer ones are dropped.
    static let capacity = 64

    /// Which slots are being taken, and the only thing the callback loads.
    let armed = Atomic<UInt32>(0)
    /// Whether an application menu is open, which returns claimed keys to the application.
    private let nativeMenuIsOpen = Atomic<Bool>(false)
    /// The accept keycode plus one, so modifier changes do not expose autorepeats during its hold.
    private let repeatingAcceptKeyCode = Atomic<UInt32>(0)
    /// The keys pressed after a taken keystroke, kept back until it has been carried out.
    let hold: KeyHold

    /// Written by the tap's thread and read by the drain; a slot is written again only once the drain has read it.
    private let ring: UnsafeMutablePointer<UInt32>
    /// Set when the tap gives up, kept out of the ring so a full ring cannot lose it.
    private let gaveUp = Atomic<Bool>(false)
    /// How many keystrokes have ever been written into the ring.
    private let written = Atomic<UInt64>(0)
    /// How many the drain has ever taken out of it.
    private let read = Atomic<UInt64>(0)
    /// The port the callback re-enables and the disables counted against it.
    let tapPort: TapPort
    /// Woken on every write, so the drain runs off the tap's own thread.
    private let signal: any DispatchSourceUserDataAdd

    init(signal: any DispatchSourceUserDataAdd, clock: some Clock<Duration> = ContinuousClock()) {
        self.signal = signal
        tapPort = TapPort(clock: clock)
        hold = KeyHold(clock: clock)
        ring = .allocate(capacity: Self.capacity)
        ring.initialize(repeating: 0, count: Self.capacity)
    }

    deinit {
        ring.deinitialize(count: Self.capacity)
        ring.deallocate()
    }

    /// Keeps a new tap's port for the callback and forgets older disables, so each tap is judged alone.
    func adopt(_ port: CFMachPort) { tapPort.adopt(port) }

    /// The port to re-enable, read only on the path where the tap has already been disabled.
    func port() -> CFMachPort? { tapPort.port() }

    /// Records one taken keystroke, or drops it and returns false when the drain is a whole ring behind.
    @discardableResult
    func enqueue(_ slot: UInt32) -> Bool {
        let next = written.load(ordering: .relaxed)
        // Acquiring pairs with the drain's releasing store, so a slot is read before it is written again.
        guard next &- read.load(ordering: .acquiring) < UInt64(Self.capacity) else { return false }
        ring[Int(next % UInt64(Self.capacity))] = slot
        written.store(next &+ 1, ordering: .releasing)
        signal.add(data: 1)
        return true
    }

    /// Whether the tap should be turned back on, which it is unless it keeps being disabled within a short window.
    func shouldReEnable() -> Bool {
        let reEnable = tapPort.shouldReEnable()
        if !reEnable {
            gaveUp.store(true, ordering: .releasing)
            signal.add(data: 1)
        }
        return reEnable
    }

    /// Takes an armed key into the ring, arming Return for a captured arrow; false if unarmed or the ring is full.
    @discardableResult
    func takeIfArmed(_ slot: ArmedKeys) -> Bool {
        guard armed.load(ordering: .relaxed) & slot.rawValue != 0 else { return false }
        guard enqueue(slot.rawValue) else { return false }
        // Claims Return only for a captured arrow, so a rejected arrow never blocks a Return the app should see.
        if slot == .optionDownArrow || slot == .optionUpArrow {
            armed.bitwiseOr(ArmedKeys.return.rawValue, ordering: .relaxed)
        }
        return true
    }

    /// Whether the tap must stay on: a slot is armed, or keys are being held behind a taken keystroke.
    var isListening: Bool { armed.load(ordering: .relaxed) != 0 || hold.isHolding }

    /// Arms `keys` and answers whether the tap stays on, which it does through a hold even with nothing armed.
    func arm(_ keys: ArmedKeys) -> Bool {
        armed.store(keys.rawValue, ordering: .relaxed)
        return isListening
    }

    /// Stops taking keys and clears the state that could swallow a later repeat.
    func stop() {
        setNativeMenuIsOpen(false)
        armed.store(0, ordering: .relaxed)
        _ = releaseHeldKeys()
    }

    /// Updates whether a native menu owns its keyboard gestures.
    func setNativeMenuIsOpen(_ isOpen: Bool) {
        nativeMenuIsOpen.store(isOpen, ordering: .releasing)
    }

    /// Replays the held keys and answers whether the tap stays on now that nothing is held.
    func releaseHeldKeys(post: (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }) -> Bool {
        // A held bare Tab is replayed only for a current bare-Tab offer, so the disarmed accept gap cannot leak literal input.
        let suppressUnarmedTab = hold.isHoldingBareTabAccept
        hold.release(
            post: post,
            where: { event in shouldReplayHeldKey(event, suppressUnarmedTab: suppressUnarmedTab) })
        repeatingAcceptKeyCode.store(0, ordering: .releasing)
        return isListening
    }

    /// Decides one real key-down on the tap's thread, answering true when it is taken or held back.
    func takes(
        _ event: CGEvent,
        postExpired: (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }
    ) -> Bool {
        let suppressUnarmedTab = hold.isHoldingBareTabAccept
        let shouldReplayHeldKey: (CGEvent) -> Bool = { event in
            self.shouldReplayHeldKey(event, suppressUnarmedTab: suppressUnarmedTab)
        }
        if hold.expireIfNeeded(post: postExpired, where: shouldReplayHeldKey) {
            repeatingAcceptKeyCode.store(0, ordering: .releasing)
        }
        let keyCode = UInt32(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let encodedKeyCode = keyCode &+ 1
        let stroke = KeyStroke(
            keyCode: UInt16(truncatingIfNeeded: keyCode),
            modifiers: KeyModifiers(event.flags))
        let slot = ArmedKeys.slot(of: stroke)
        let repeatingKeyCode = repeatingAcceptKeyCode.load(ordering: .acquiring)
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            repeatingKeyCode != 0,
            repeatingKeyCode == encodedKeyCode
        {
            return true
        }
        if repeatingKeyCode != 0, repeatingKeyCode != encodedKeyCode {
            repeatingAcceptKeyCode.store(0, ordering: .releasing)
        }
        // A key pressed while a taken keystroke is carried out waits for it, so it cannot overtake an insertion.
        if hold.keep(event, postExpired: postExpired, where: shouldReplayHeldKey) { return true }
        guard !nativeMenuIsOpen.load(ordering: .acquiring) else { return false }
        guard route(slot) else { return false }
        repeatingAcceptKeyCode.store(encodedKeyCode, ordering: .releasing)
        hold.begin(suppressingUnarmedTab: stroke == KeyStroke(.tab))
        return true
    }

    /// Applies the same bare-Tab rule to a finished hold and one that reaches its deadline.
    private func shouldReplayHeldKey(_ event: CGEvent, suppressUnarmedTab: Bool) -> Bool {
        guard suppressUnarmedTab else { return true }
        let stroke = KeyStroke(
            keyCode: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
            modifiers: KeyModifiers(event.flags))
        let bareTabIsArmed = armed.load(ordering: .acquiring) & ArmedKeys.tab.rawValue != 0
        return stroke != KeyStroke(.tab) || bareTabIsArmed
    }

    /// Takes an armed key, or disarms every slot for a key the application will see, so a later accept cannot take a stale offer.
    func route(_ slot: ArmedKeys) -> Bool {
        if !slot.isEmpty, takeIfArmed(slot) { return true }
        armed.store(0, ordering: .relaxed)
        return false
    }

    /// Everything written since the last drain, oldest first, then the tap giving up if it has.
    func take() -> [InterceptedEvent] {
        // Read before `written`, so every keystroke taken before the tap gave up is drained with it.
        let stopped = gaveUp.exchange(false, ordering: .acquiring)
        let end = written.load(ordering: .acquiring)
        var cursor = read.load(ordering: .relaxed)
        var events: [InterceptedEvent] = []
        while cursor < end {
            let slot = ring[Int(cursor % UInt64(Self.capacity))]
            if let stroke = ArmedKeys.stroke(of: ArmedKeys(rawValue: slot)) {
                events.append(.swallowed(stroke))
            }
            cursor &+= 1
        }
        // Releasing, so the tap writes these slots again only after they have been read.
        read.store(cursor, ordering: .releasing)
        if stopped { events.append(.stopped(.disabledTwice)) }
        return events
    }
}
