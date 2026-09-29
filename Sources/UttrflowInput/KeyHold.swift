internal import CoreGraphics
internal import Dispatch
internal import Synchronization

/// Keys pressed between a swallowed keystroke and its handling, kept back and replayed in order afterwards.
final class KeyHold: Sendable {
    /// How long a hold may last before keys pass through again, so a stalled handler never keeps the keyboard.
    static let limitNanoseconds: UInt64 = 1_000_000_000

    /// When the hold began, in uptime nanoseconds, or zero when nothing is held back.
    private let since = Atomic<UInt64>(0)
    /// Whether a bare Tab accept must not be replayed into a disarmed gap.
    private let suppressUnarmedTab = Atomic<Bool>(false)
    /// The key-downs kept back, oldest first.
    private let kept = Mutex<[Kept]>([])

    /// A copied event, owned by the hold alone from the moment it is kept.
    private struct Kept: @unchecked Sendable {
        let event: CGEvent
    }

    /// Starts holding keys back, from the moment a keystroke is swallowed on the tap's thread.
    func begin(now: UInt64 = DispatchTime.now().uptimeNanoseconds, suppressingUnarmedTab: Bool = false) {
        suppressUnarmedTab.store(suppressingUnarmedTab, ordering: .relaxed)
        since.store(max(now, 1), ordering: .releasing)
    }

    /// Whether keys are being held back, which keeps the tap on while nothing is armed.
    var isHolding: Bool { since.load(ordering: .acquiring) != 0 }

    /// Whether the swallowed key was bare Tab, which can leak as literal input during accept.
    var isHoldingBareTabAccept: Bool { suppressUnarmedTab.load(ordering: .acquiring) }

    /// Keeps a copy of a key-down back and returns true while a hold is in force; false lets it through.
    func keep(_ event: CGEvent, now: UInt64 = DispatchTime.now().uptimeNanoseconds) -> Bool {
        let start = since.load(ordering: .acquiring)
        guard start != 0 else { return false }
        guard now &- start < Self.limitNanoseconds else {
            since.store(0, ordering: .releasing)
            return false
        }
        guard let copy = event.copy() else { return false }
        kept.withLock { $0.append(Kept(event: copy)) }
        return true
    }

    /// Ends the hold and hands each allowed key-down to `post`, oldest first.
    func release(
        post: (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) },
        where shouldPost: (CGEvent) -> Bool = { _ in true }
    ) {
        since.store(0, ordering: .releasing)
        let events = kept.withLock { kept in
            defer { kept.removeAll() }
            return kept
        }
        suppressUnarmedTab.store(false, ordering: .releasing)
        for kept in events where shouldPost(kept.event) { post(kept.event) }
    }
}
