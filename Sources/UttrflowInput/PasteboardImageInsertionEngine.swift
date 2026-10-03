public import struct Foundation.Data
public import UttrflowCore

/// Pastes an image from the clipboard panel without sending it into Uttrflow itself.
public struct PasteboardImageInsertionEngine: Sendable {
    private let focus: any AccessibilityFocus
    private let pasteboard: any Pasteboard
    private let keystrokes: any KeystrokeSender

    public init(
        focus: any AccessibilityFocus, pasteboard: any Pasteboard,
        keystrokes: any KeystrokeSender
    ) {
        self.focus = focus
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
    }

    /// Writes the image and posts ⌘V only if an external application remains frontmost.
    public func insert(_ data: Data) throws(TextInsertionError) {
        try PasteboardPasteAction.requireExternal(focus: focus)
        guard pasteboard.setImage(data).didWrite else { throw .clipboardUnavailable }
        try PasteboardPasteAction.postIfExternal(focus: focus, keystrokes: keystrokes)
    }
}
