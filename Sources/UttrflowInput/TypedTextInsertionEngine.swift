import Synchronization
import Foundation

public import UttrflowCore

/// Types text as key events, the one route into a hidden field that never borrows the clipboard.
public protocol KeystrokeTyping: Sendable {
    /// Types `text` into whatever has focus.
    func type(_ text: String) throws(TextInsertionError)

    /// Presses Delete `count` times, which is the only way this route takes typed characters back.
    func deleteBackwards(_ count: Int) throws(TextInsertionError)
}

/// Puts text in by typing it, for the fields Accessibility cannot write into.
public struct TypedTextInsertionEngine: TextInsertionEngine {
    public let method: TextInsertionMethod = .typed

    private let focus: any AccessibilityFocus
    private let typist: any KeystrokeTyping
    private let writeState = TypedWriteState()

    public init(focus: any AccessibilityFocus, typist: any KeystrokeTyping) {
        self.focus = focus
        self.typist = typist
    }

    /// Anything but ourselves; Electron apps expose no focused element and still take typing.
    public func canInsert() async -> Bool { !focus.isSelfFrontmost() }

    /// Answers `.notReported`: a key event posted is not a character accepted, and nothing reads it back.
    public func insert(_ text: String) async throws(TextInsertionError) -> InsertionArrival {
        try refuseIfSelfFrontmost()
        try typist.type(text)
        return .notReported
    }
}

extension TypedTextInsertionEngine: CompletionWriting {
    public func canWrite() async -> Bool { await canInsert() }

    /// Waits for an in-flight replacement before the application terminates.
    public func finishWrites() async { await writeState.closeAndWait() }

    /// Backspaces then types, which the target's undo sees as several edits. See `Docs/predict-accept.md`.
    public func write(_ text: String, replacing replaced: String) async throws(TextInsertionError) {
        try await write(text, replacing: replaced, confirmedPreceding: nil)
    }

    public func write(
        _ text: String, replacing replaced: String, confirmedPreceding: String?
    ) async throws(TextInsertionError) {
        guard let write = writeState.begin() else {
            throw .insertionRejected(description: "the application is terminating")
        }
        defer { writeState.end(write) }
        let count = replaced.count
        if count > 0 {
            // A blind backspace could eat a shell prompt, so what is there is checked when the field will say.
            let preceding: String?
            if let confirmedPreceding {
                preceding = confirmedPreceding
            } else {
                let focus = focus
                preceding = await AccessibilityThread.run(orElse: nil) { focus.precedingText(count) }
            }
            if let preceding, preceding != replaced {
                throw .insertionRejected(
                    description: "the text before the caret is not what would be replaced")
            }
            try refuseIfSelfFrontmost()
            try typist.deleteBackwards(count)
        } else {
            try refuseIfSelfFrontmost()
        }
        try typist.type(text)
    }
}

/// Tracks typed writes across their suspension points so quit waits through deletion and typing.
private final class TypedWriteState: Sendable {
    private struct State {
        var active: Set<UUID> = []
        var waiters: [CheckedContinuation<Void, Never>] = []
        var isClosed = false
    }

    private let state = Mutex(State())

    func begin() -> UUID? {
        state.withLock { state in
            guard !state.isClosed else { return nil }
            let id = UUID()
            state.active.insert(id)
            return id
        }
    }

    func end(_ id: UUID) {
        let waiting = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.active.remove(id)
            guard state.active.isEmpty else { return [] }
            defer { state.waiters.removeAll() }
            return state.waiters
        }
        for continuation in waiting { continuation.resume() }
    }

    func closeAndWait() async {
        await withCheckedContinuation { continuation in
            let resumeNow = state.withLock { state -> Bool in
                state.isClosed = true
                guard !state.active.isEmpty else { return true }
                state.waiters.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }
}

extension TypedTextInsertionEngine {
    /// Re-checked at the write rather than trusted from `canInsert()`, whose answer can go stale by now.
    private func refuseIfSelfFrontmost() throws(TextInsertionError) {
        guard !focus.isSelfFrontmost() else { throw .noFocusedTextField }
    }
}
