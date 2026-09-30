// Refreshes the Settings page while its visible Suggestions pause is running.

import Foundation
import UttrflowUX

@MainActor
enum SettingsPauseCountdown {
    /// Returns a deadline only while the unfiltered Suggestions pane is visible.
    static func deadline(in session: SettingsSession) -> Date? {
        guard session.tab == .suggestions, session.query.isEmpty else { return nil }
        return session.settings.suggestions.pausedUntil
    }

    /// Ticks once a minute and once after the deadline, stopping when SwiftUI cancels its task.
    static func follow<C: Clock>(
        until deadline: Date,
        clock: C,
        now: @MainActor () -> Date,
        onTick: @MainActor () -> Void
    ) async where C.Duration == Duration {
        while !Task.isCancelled {
            let remaining = deadline.timeIntervalSince(now())
            guard remaining > 0 else { return }
            try? await clock.sleep(for: .seconds(min(60, remaining) + 0.5))
            guard !Task.isCancelled else { return }
            onTick()
        }
    }
}
