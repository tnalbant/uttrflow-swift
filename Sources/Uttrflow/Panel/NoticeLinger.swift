// The timer that closes the panel after a notice, unless the person goes on using it.

import Foundation

/// Closes the panel once a notice has been read, and never while the person is still working in it.
@MainActor
final class NoticeLinger {
    /// Long enough to read one short sentence and no more, since the panel is in the way.
    static let standard = Duration.seconds(2.5)

    private let linger: Duration
    private let sleep: @MainActor @Sendable (Duration) async -> Void
    private var task: Task<Void, Never>?

    init(
        linger: Duration = NoticeLinger.standard,
        sleep: @escaping @MainActor @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.linger = linger
        self.sleep = sleep
    }

    /// Whether a close is still waiting to happen.
    var isPending: Bool { task != nil }

    /// Starts the wait again; `close` runs only if nothing interrupts it first.
    func start(close: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { [weak self, linger, sleep] in
            await sleep(linger)
            guard !Task.isCancelled else { return }
            self?.task = nil
            close()
        }
    }

    /// Called on any key or intent, so the panel stays while it is in use.
    func interrupt() {
        task?.cancel()
        task = nil
    }
}
