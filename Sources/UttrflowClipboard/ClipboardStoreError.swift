// Errors the clipboard store can report.

public import UttrflowCore

/// A failure while keeping the clipboard.
public enum ClipboardStoreError: UttrflowFailure {
    /// The clipboard file could not be written or removed.
    case couldNotWrite
    /// Another clip already answers to the alias.
    case aliasAlreadyInUse

    public var userMessage: String {
        switch self {
        case .couldNotWrite: "Your clipboard history could not be updated on this Mac."
        case .aliasAlreadyInUse: "That name already belongs to another clip."
        }
    }

    /// Choosing another alias is an ordinary edit, not a recovery action.
    public var recovery: RecoveryAction? { nil }

    /// Degraded, not blocking: the clipboard still works and the panel still opens on what it had.
    public var severity: FailureSeverity { .degraded }
}

extension ClipboardStoreError: CataloguedFailure {
    public static var firstCase: Self { .couldNotWrite }

    public var caseAfter: Self? {
        switch self {
        case .couldNotWrite: .aliasAlreadyInUse
        case .aliasAlreadyInUse: nil
        }
    }
}
