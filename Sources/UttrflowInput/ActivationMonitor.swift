import Dispatch
import Foundation
import Synchronization
private import OSLog

public import UttrflowCore

/// Watches for the chosen shortcut through one source and one recogniser. See `Docs/shortcuts.md`.
public final class ActivationMonitor: HotkeyMonitoring {
    /// Where a tap giving up, and its rebuild, are said so the failure leaves a trace.
    private static let log = Logger(subsystem: "com.uttrflow.Uttrflow", category: "shortcuts")
    /// How long the source rests before a rebuild, past the window in which disables count against it.
    private static let defaultRestSeconds = 90

    public let events: AsyncStream<HotkeyEvent>
    private let continuation: AsyncStream<HotkeyEvent>.Continuation
    private let source: any KeyboardEventSource
    private let recogniser = Mutex<HotkeyRecogniser?>(nil)
    /// Counts starts, so a stop that began before one cannot clear the recogniser it installed.
    private let generation = Atomic<Int>(0)
    /// The binding to rebuild with, kept only for the source's own give-up-and-rebuild recovery.
    private let activeBinding = Mutex<HotkeyBinding?>(nil)
    /// The pending rebuild, cancelled by a `stop()` so it never resurrects a disabled shortcut.
    private let rebuild = Mutex<Task<Void, Never>?>(nil)
    /// Runs on the source's thread once a stroke has left the lock, so a test can hold it there.
    private let strokeLeftLock: @Sendable () -> Void
    /// Reads the real keyboard state, so a release the tap never delivers is still noticed.
    private let keyState: any RealKeyStateReading
    /// The timer comparing real keyboard state against what the recogniser was last told.
    private let reconciliation = Mutex<(any DispatchSourceTimer)?>(nil)
    /// How often that comparison runs, in milliseconds. See `Docs/stuck-recording.md`.
    private static let reconciliationMilliseconds = 250
    /// How long a give-up waits before rebuilding, overridable so a test need not wait.
    private let restSeconds: Int

    /// Takes the source it listens through, so a test can hand it strokes instead of a keyboard.
    public convenience init(source: any KeyboardEventSource = SystemKeyboard()) {
        self.init(source: source, keyState: SystemKeyState(), strokeLeftLock: {})
    }

    init(
        source: any KeyboardEventSource, keyState: any RealKeyStateReading = SystemKeyState(),
        strokeLeftLock: @escaping @Sendable () -> Void,
        restSeconds: Int = ActivationMonitor.defaultRestSeconds
    ) {
        self.source = source
        self.keyState = keyState
        self.strokeLeftLock = strokeLeftLock
        self.restSeconds = restSeconds
        (events, continuation) = AsyncStream.makeStream()
    }

    deinit {
        // Not `source.stop()`: a source this monitor owns stops itself, and reaching out here recurses.
        rebuild.withLock { $0?.cancel() }
        reconciliation.withLock { $0?.cancel() }
        continuation.finish()
    }

    @MainActor
    public func start(binding: HotkeyBinding) throws(HotkeyError) {
        stop()
        guard binding.isDeliverable else {
            throw .shortcutUnavailable
        }
        activeBinding.withLock { $0 = binding }
        recogniser.withLock { current in
            generation.add(1, ordering: .relaxed)
            current = HotkeyRecogniser(binding: binding)
        }
        source.onGaveUp { [weak self] in self?.sourceGaveUp() }
        let continuation = continuation
        do {
            try source.start(
                { [weak self] stroke in
                    guard let self else { return }
                    if stroke.keyCode == 53, stroke.phase == .down, stroke.isEmptyHold {
                        _ = recogniser.withLock { _ in continuation.yield(.escapePressed) }
                        strokeLeftLock()
                        return
                    }
                    // Yield under the lock, so a stop's owed release cannot overtake the press it ends.
                    let happened = recogniser.withLock { current -> HotkeyEvent? in
                        let happened = current?.receive(stroke)
                        if let happened { continuation.yield(happened) }
                        return happened
                    }
                    if let happened {
                        switch happened {
                        case .pressed: startReconciling(binding)
                        case .released, .cancelled, .escapePressed: stopReconciling()
                        }
                    }
                    strokeLeftLock()
                }, consumeKeyDown: false)
        } catch {
            throw .observationNotPermitted
        }
    }

    public func stop() {
        rebuild.withLock {
            $0?.cancel(); $0 = nil
        }
        TeardownGuard.once(for: self) {
            let began = recogniser.withLock { _ in generation.load(ordering: .relaxed) }
            source.stop()
            stopReconciling()
            // A hold interrupted by stopping is a release, or the microphone stays open.
            recogniser.withLock { current in
                guard generation.load(ordering: .relaxed) == began else { return }
                if let owed = current?.finish() { continuation.yield(owed) }
                current = nil
            }
        }
    }

    /// The source left its tap off; release any hold it can no longer report, rest, then rebuild it.
    private func sourceGaveUp() {
        Self.log.error("the shortcut's tap gave up; rebuilding after \(self.restSeconds, privacy: .public)s")
        stopReconciling()
        // Not `source.stop()`: the tap is already off, and teardown from its callback can recurse.
        recogniser.withLock { current in
            if let owed = current?.finish() { continuation.yield(owed) }
            current = nil
        }
        rebuild.withLock {
            $0?.cancel()
            $0 = Task { @MainActor [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: .seconds(self.restSeconds))
                guard !Task.isCancelled, let binding = activeBinding.withLock({ $0 }) else { return }
                do {
                    try start(binding: binding)
                    Self.log.error(
                        "the shortcut's tap is back after resting \(self.restSeconds, privacy: .public)s")
                } catch {
                    Self.log.error(
                        "the shortcut's tap could not rebuild: \(String(describing: error), privacy: .public)"
                    )
                }
            }
        }
    }

    // MARK: Reconciliation

    /// Reads real key state so a release the tap never delivers is still noticed.
    private func startReconciling(_ binding: HotkeyBinding) {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + .milliseconds(Self.reconciliationMilliseconds),
            repeating: .milliseconds(Self.reconciliationMilliseconds))
        timer.setEventHandler { [weak self] in
            // A monitor released mid-hold cancels its own timer rather than firing forever.
            guard let self else { timer.cancel(); return }
            guard recogniser.withLock({ $0?.isDown }) == true else { return }
            guard !keyState.isDown(binding) else { return }
            deliverReconciledRelease()
        }
        timer.resume()
        reconciliation.withLock { existing in
            existing?.cancel()
            existing = timer
        }
    }

    private func stopReconciling() {
        reconciliation.withLock { timer in
            timer?.cancel()
            timer = nil
        }
    }

    /// Delivers the release the poll found, the same way an owed release from `stop()` is delivered.
    private func deliverReconciledRelease() {
        let owed = recogniser.withLock { current in current?.finish() }
        guard let owed else { return }
        continuation.yield(owed)
        stopReconciling()
    }
}
