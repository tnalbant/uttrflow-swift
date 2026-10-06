// Tells a running build that holds no startup lock apart from a racing launch that is about to exit.

import Foundation

/// Decides by liveness, not lock ownership, whether another running build is a lasting conflict.
public enum LocklessPeer {
    /// How long a startup loser has to exit before a lockless peer counts as a lasting conflict.
    public static let exitWindow: Duration = .seconds(5)

    /// Whether a peer whose locks were free is still running once `window` has passed.
    public static func outlasts(
        within window: Duration = exitWindow, pollingEvery interval: Duration = .milliseconds(50),
        isRunning: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(SingleInstanceLock.seconds(window))
        let pause = SingleInstanceLock.seconds(interval)
        while isRunning() {
            guard Date() < deadline else { return true }
            Thread.sleep(forTimeInterval: pause)
        }
        return false
    }
}
