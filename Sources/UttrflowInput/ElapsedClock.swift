/// An injected `Clock` read as nanoseconds since it was adopted, for time the tap's thread keeps in atomics.
struct ElapsedClock: Sendable {
    /// Reads the clock and answers how far it has moved since adoption.
    private let read: @Sendable () -> Duration

    /// Adopts `clock`, so its present instant becomes the origin every later reading is measured from.
    init<C: Clock<Duration>>(_ clock: C = ContinuousClock()) {
        let origin = clock.now
        read = { origin.duration(to: clock.now) }
    }

    /// Nanoseconds since adoption plus one, so a reading is never the 0 its callers keep for "none".
    var nanoseconds: UInt64 {
        let (seconds, attoseconds) = read().components
        return UInt64(max(seconds, 0)) &* 1_000_000_000 &+ UInt64(max(attoseconds, 0) / 1_000_000_000) &+ 1
    }
}
