// The one rule behind "deleted after N days", shared by every store that makes the promise.

public import struct Foundation.Date

/// A retention promise and the clock it is measured against, which it does not trust. See `Docs/retention-clock.md`.
public struct RetentionWindow: Sendable, Equatable {
    /// The stored day value for keeping transcripts until the user deletes them.
    public static let keepAlwaysDays = 36_500

    /// A stamp this far ahead of `now` is taken at face value, since a clock nudged by a second is not a wrong one.
    static let clockSkewAllowance: Double = 300

    /// How far ahead of a record this clock may claim to be and still be believed enough to delete it.
    static let longestBelievableIdle: Double = 365 * 86_400

    /// How long a record is kept, measured from its own stamp; zero or less keeps nothing.
    public let span: Double

    /// The instant the window is measured against: the caller's clock, never read here.
    public let now: Date

    /// Pairs a window in whole days with the moment it is measured from.
    public init(days: Int, now: Date) {
        self.init(span: Double(days) * 86_400, now: now)
    }

    /// Pairs a window in seconds with the moment it is measured from, for a window shorter than a day.
    public init(span: Double, now: Date) {
        self.span = span
        self.now = now
    }

    /// Whether a record stamped `when` is still inside the window; one stamped ahead of the clock is due.
    public func keeps(_ when: Date) -> Bool {
        guard span > 0 else { return false }
        guard when <= now.addingTimeInterval(Self.clockSkewAllowance) else { return false }
        return when.addingTimeInterval(span) > now
    }

    /// Whether this clock is believable enough to delete a record stamped `when`, rather than only hide it.
    public func mayDelete(_ when: Date) -> Bool {
        now.timeIntervalSince(when) <= Self.longestBelievableIdle
    }

    /// The same pair of answers as a range, for a stamp that lives in a file name rather than in a record.
    public var sweepable: Range<Date> {
        // A window of nothing keeps nothing, so every stamp this clock is believed about is due.
        let due =
            span > 0
            ? now.addingTimeInterval(-span) : now.addingTimeInterval(Self.clockSkewAllowance)
        // Empty rather than invalid when the window itself outruns what this clock is believed about.
        return min(now.addingTimeInterval(-Self.longestBelievableIdle), due)..<due
    }
}
