public import UttrflowCore
public import struct Foundation.Data

/// The system clipboard, reduced to what insertion needs and testable without touching the real one.
public protocol Pasteboard: Sendable {
    /// The current text, or `nil` when the clipboard holds something else.
    func text() -> String?
    /// A token that changes whenever the clipboard is written, or `nil` when ownership cannot be observed.
    func changeCount() -> Int?
    /// Replaces the contents.
    func setText(_ text: String)

    /// The same write, with the formatted flavour alongside where there is one.
    func setText(_ text: String, richText: String?)

    /// Replaces the contents with words marked concealed, so clipboard histories keep them out.
    func setConcealedText(_ text: String)

    /// Writes text and returns the generation created by that write.
    func writeText(_ text: String, richText: String?) -> Int?

    /// Writes concealed text and returns the generation created by that write.
    func writeConcealedText(_ text: String) -> Int?

    /// K4 — replaces the contents with a picture, as PNG bytes, so no caller needs the platform clipboard.
    func setImage(_ data: Data)
}

/// Sends the keystroke that pastes.
public protocol KeystrokeSender: Sendable {
    /// Presses ⌘V, refusing with ``TextInsertionError/accessibilityDenied`` where macOS forbids it.
    func sendPaste() throws(TextInsertionError)
}

extension Pasteboard {
    /// Test doubles and pasteboards without ownership tracking may decline this check.
    public func changeCount() -> Int? { nil }

    /// A pasteboard that cannot carry formatting simply writes the words.
    public func setText(_ text: String, richText: String?) { setText(text) }

    /// Captures the generation immediately after the write.
    public func writeText(_ text: String, richText: String?) -> Int? {
        setText(text, richText: richText)
        return changeCount()
    }

    /// Captures the generation immediately after the concealed write.
    public func writeConcealedText(_ text: String) -> Int? {
        setConcealedText(text)
        return changeCount()
    }
}
