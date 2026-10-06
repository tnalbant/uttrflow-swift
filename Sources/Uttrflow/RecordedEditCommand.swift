// "delete that", "select that" and "undo that" under the command key, on the last dictation. See `Docs/commands.md`.
import UttrflowCore
import UttrflowInput
import UttrflowPipeline

/// The command-key edits that act on what Uttrflow last wrote, located through the insertion ledger.
struct RecordedEditCommand: EditCommand {
    private let editor: RecordedEditor

    init(ledger: InsertionLedger, history: EditHistory = EditHistory()) {
        editor = RecordedEditor(ledger: ledger, history: history, focus: AXAccessibilityFocus())
    }

    func accepts(_ heard: String) -> Bool { RecordedEdit(heard: heard) != nil }

    func run(_ heard: String, on target: AppContext) async throws {
        guard let edit = RecordedEdit(heard: heard) else { return }
        try await editor.run(edit)
    }
}
