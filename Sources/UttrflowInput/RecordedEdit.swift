// Runs "delete that", "select that" and "undo that" on the last dictation, by its recorded range. See `Docs/commands.md`.
public import UttrflowCore

/// One spoken edit on the last dictation; it only removes or selects what Uttrflow wrote, never rewrites a word.
public enum RecordedEdit: String, Sendable, CaseIterable {
    /// Takes the last dictation out of the field.
    case delete
    /// Selects the last dictation.
    case select
    /// Undoes the last spoken edit, or, with none to undo, takes the last dictation out.
    case undo

    /// The edit the whole utterance names, ignoring the recogniser's case and closing mark; nil for anything else.
    public init?(heard: String) {
        let keys = heard.split(whereSeparator: \.isWhitespace).map { WordShape(String($0)).key }
        guard keys.count == 2, keys[1] == "that", let edit = RecordedEdit(rawValue: keys[0]) else {
            return nil
        }
        self = edit
    }
}

/// The field writes a recorded edit needs, which only an Accessibility field that reads ranges offers.
protocol RecordedSpanEditing: Sendable {
    func edit(_ target: EditTarget, to text: String) throws(TextInsertionError) -> EditUndo
    func select(_ target: EditTarget) throws(TextInsertionError)
    func undo(from history: EditHistory, focused: FieldIdentity?, isSecure: Bool) throws(TextInsertionError)
}

extension SelectionWriter: RecordedSpanEditing {}

/// Carries out a `RecordedEdit` in the focused field, against the ledger of confirmed insertions.
public struct RecordedEditor: Sendable {
    private let ledger: InsertionLedger
    private let history: EditHistory
    private let focus: any AccessibilityFocus

    public init(ledger: InsertionLedger, history: EditHistory, focus: any AccessibilityFocus) {
        self.ledger = ledger
        self.history = history
        self.focus = focus
    }

    /// Runs `edit` on the field in front; it throws, changing nothing, unless the dictation is still exactly there.
    public func run(_ edit: RecordedEdit) async throws(TextInsertionError) {
        let focus = focus
        let ledger = ledger
        let history = history
        try await AccessibilityThread.run { () throws(TextInsertionError) in
            let focused = focus.focusedFieldIdentity()
            let secure = focus.focusedFieldIsSecure()
            guard let field = focus.focusedTextField() as? any RecordedSpanEditing else {
                throw .insertionRejected(description: "the field cannot edit by range")
            }
            try Self.apply(
                edit, to: field, ledger: ledger, history: history, focused: focused, isSecure: secure)
        }
    }

    /// Applies `edit` to `field`; split out so it runs against a fake field in tests.
    static func apply(
        _ edit: RecordedEdit, to field: any RecordedSpanEditing, ledger: InsertionLedger,
        history: EditHistory, focused: FieldIdentity?, isSecure: Bool
    ) throws(TextInsertionError) {
        if edit == .undo, history.holdsEdit(in: focused) {
            try field.undo(from: history, focused: focused, isSecure: isSecure)
            return
        }
        guard let record = CommandScope.default.span(in: ledger.records(in: focused)) else {
            throw .insertionRejected(description: "there is no dictation here to edit")
        }
        let target = EditTarget(record: record, focused: focused, isSecure: isSecure)
        switch edit {
        case .select:
            try field.select(target)
        case .delete, .undo:
            do {
                history.note(try field.edit(target, to: ""))
            } catch {
                ledger.clear()
                throw error
            }
            // Offsets after the cut name other text now, so none is kept.
            ledger.clear()
        }
    }
}
