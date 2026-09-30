/// A failure while placing text into another application.
public enum TextInsertionError: UttrflowFailure {
    /// Nothing on screen accepts text.
    case noFocusedTextField
    /// macOS will not let this process drive other apps.
    case accessibilityDenied
    /// The clipboard itself refused the text.
    case clipboardUnavailable
    /// Another process replaced the clipboard during insertion, so its newer contents are preserved.
    case clipboardChanged
    /// The insertion deadline passed before any delivery result was confirmed.
    case insertionTimedOut
    /// The focused app refused the text, which is on the clipboard instead.
    case insertionRejected(description: String)
    /// Accessibility accepted a write but its delayed result could not be distinguished from refusal.
    case insertionUnconfirmed
    /// The application in front changed after the destination was captured.
    case insertionTargetChanged

    /// A plain sentence per case, saying where the words are.
    public var userMessage: String {
        switch self {
        case .noFocusedTextField:
            "There's no text field to type into. Your dictation is saved under Recent in the menu bar."
        case .accessibilityDenied:
            "Accessibility access is required to insert text into other applications."
        case .clipboardUnavailable:
            "The text couldn't be inserted or copied. It's kept under Recent in the menu bar."
        case .clipboardChanged:
            "Your clipboard changed during insertion. Your dictation is saved under Recent in the menu bar."
        case .insertionTimedOut:
            "The application did not respond. Your dictation is saved under Recent in the menu bar."
        case .insertionRejected:
            "The text couldn't be inserted here. It's been copied, so press ⌘V to paste it."
        case .insertionUnconfirmed:
            "The app hasn't confirmed whether the text was inserted. Check the field before trying again."
        case .insertionTargetChanged:
            "The app in front changed. Focus the intended field and try again."
        }
    }

    /// Wherever the words are: the clipboard, or Recent when the clipboard is what failed.
    public var recovery: RecoveryAction? {
        switch self {
        case .noFocusedTextField: .showRecentDictations
        case .accessibilityDenied: .openSystemSettings(.accessibility)
        // The clipboard failed, so "paste" would point at the one place the words are not.
        case .clipboardUnavailable: .showRecentDictations
        case .clipboardChanged: .showRecentDictations
        case .insertionTimedOut: .showRecentDictations
        case .insertionTargetChanged: .showRecentDictations
        case .insertionRejected: .pasteManually
        case .insertionUnconfirmed: .showRecentDictations
        }
    }

    /// Recoverable when nothing was focused; degraded otherwise, since the words exist and are reachable.
    public var severity: FailureSeverity {
        switch self {
        // Nothing on screen took the text this once; the next attempt, with something focused, does.
        case .noFocusedTextField: .recoverable
        // The words exist and the user can reach them; they only missed where they were aimed.
        case .accessibilityDenied, .clipboardUnavailable, .clipboardChanged, .insertionTimedOut,
            .insertionRejected,
            .insertionUnconfirmed, .insertionTargetChanged:
            .degraded
        }
    }

    /// Whether another route must not attempt the same insertion.
    public var stopsFallback: Bool {
        switch self {
        case .insertionUnconfirmed, .insertionTargetChanged, .clipboardChanged: true
        default: false
        }
    }
}
