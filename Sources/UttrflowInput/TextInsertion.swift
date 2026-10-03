public import UttrflowCore

/// Builds the insertion strategies in the order they are tried, and is the one place that names them.
public enum TextInsertion {
    /// The words a stage that has already given up must not write; a late paste is the user's clipboard gone.
    static let dictationEnded = "the dictation had already given up on this insertion"

    /// Accessibility, then pasting, typing and optionally the clipboard; `only` keeps one of them. See `Docs/insertion.md`.
    public static func coordinator(
        focus: any AccessibilityFocus = AXAccessibilityFocus(),
        pasteboard: any Pasteboard = SystemPasteboard(),
        keystrokes: any KeystrokeSender = CGEventKeystrokeSender(),
        typist: any KeystrokeTyping = CGEventTypist(),
        confirmsArrival: Bool = true,
        reporting: (@Sendable (PasteConfirmation.Outcome) -> Void)? = nil,
        clipboardFallback: Bool = true,
        only: TextInsertionMethod? = nil
    ) -> TextInsertionCoordinator {
        var strategies: [any TextInsertionEngine] = [
            AccessibilityTextInsertionEngine(focus: focus),
            PasteboardTextInsertionEngine(
                focus: focus, pasteboard: pasteboard, keystrokes: keystrokes,
                confirmsArrival: confirmsArrival,
                reporting: reporting),
        ]
        if clipboardFallback {
            strategies.append(ClipboardTextInsertionEngine(pasteboard: pasteboard, focus: focus))
        } else {
            strategies.append(TypedTextInsertionEngine(focus: focus, typist: typist))
        }
        if let only { strategies = strategies.filter { $0.method == only } }
        return TextInsertionCoordinator(strategies: strategies, focus: focus)
    }

    /// Dictation never writes the clipboard: after Accessibility, it types or leaves the transcript for explicit copy.
    public static func dictation(
        focus: any AccessibilityFocus = AXAccessibilityFocus(),
        typist: any KeystrokeTyping = CGEventTypist()
    ) -> TextInsertionCoordinator {
        TextInsertionCoordinator(
            strategies: [
                AccessibilityTextInsertionEngine(focus: focus),
                TypedTextInsertionEngine(focus: focus, typist: typist),
            ], focus: focus)
    }

    /// The route an accepted suggestion takes, which has no clipboard in it at all. See `Docs/predict-accept.md`.
    public static func completion(
        focus: any AccessibilityFocus = AXAccessibilityFocus(),
        typist: any KeystrokeTyping = CGEventTypist()
    ) -> CompletionRoute {
        CompletionRoute(strategies: [
            AccessibilityTextInsertionEngine(focus: focus),
            TypedTextInsertionEngine(focus: focus, typist: typist),
        ])
    }
}
