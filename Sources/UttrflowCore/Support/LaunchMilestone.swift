import OSLog

/// Records the launch's first shortcut arming once, as a log line and a signpost. See `Docs/startup.md`.
@MainActor
public final class LaunchMilestone {
    /// Where the line is logged, so `uttrflow-dev launch` and `log show` read the same place.
    public nonisolated static let subsystem = "com.uttrflow.Uttrflow"
    public nonisolated static let category = "launch"

    private static let log = Logger(subsystem: subsystem, category: category)
    private static let signposter = OSSignposter(subsystem: subsystem, category: category)

    private let processAge: () -> Duration?
    /// The first outcome, kept so a later re-arming from Settings is never taken for the launch.
    public private(set) var report: LaunchReport?

    public init(processAge: @escaping () -> Duration? = ProcessAge.current) {
        self.processAge = processAge
    }

    /// Records the outcome the first time only, and returns what was recorded then.
    @discardableResult
    public func shortcutSettled(_ outcome: LaunchReport.Outcome) -> LaunchReport? {
        guard report == nil else { return nil }
        let settled = LaunchReport(age: processAge(), outcome: outcome)
        report = settled
        Self.signposter.emitEvent("ShortcutSettled", "\(settled.logged, privacy: .public)")
        Self.log.notice("\(settled.logged, privacy: .public)")
        return settled
    }
}
