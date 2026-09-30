// When Sparkle's own automatic checks may start, so one never races the speech model load.

/// Whether an automatic check may start: only once configured and the speech model has settled.
public struct UpdateStartupGate: Sendable, Equatable {
    public private(set) var isConfigured = false
    public private(set) var hasSettled = false
    public private(set) var hasStarted = false

    public init() {}

    /// Records that `UpdateController.begin` has run; does not by itself allow a start.
    public mutating func configure() {
        isConfigured = true
    }

    /// Records that the speech model has finished loading, failed to, or was never installed.
    public mutating func settle() {
        hasSettled = true
    }

    /// Whether this call is the one that should start Sparkle automatically, given the state so far.
    public mutating func mayStartAutomatically() -> Bool {
        guard isConfigured, hasSettled, !hasStarted else { return false }
        hasStarted = true
        return true
    }

    /// A user-requested check: configures if it has not already, and always starts on its first call.
    public mutating func mayStartManually() -> Bool {
        configure()
        guard !hasStarted else { return false }
        hasStarted = true
        return true
    }
}
