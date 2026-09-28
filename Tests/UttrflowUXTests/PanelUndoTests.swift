// Tests what ⌘Z undoes in the panel: typing first, then the last delete, else nothing.
import Testing

@testable import UttrflowUX

@Suite("What ⌘Z undoes in the panel")
struct PanelUndoTests {
    @Test("typing in the field is undone ahead of a deleted clip")
    func typingComesFirst() {
        #expect(PanelUndo.choose(fieldCanUndo: true, canUndoDelete: true) == .typing)
        #expect(PanelUndo.choose(fieldCanUndo: true, canUndoDelete: false) == .typing)
    }

    @Test("with no typing to undo, the last deleted clip comes back")
    func deleteWhenNoTyping() {
        #expect(PanelUndo.choose(fieldCanUndo: false, canUndoDelete: true) == .delete)
    }

    @Test("with neither, nothing is undone")
    func nothingOtherwise() {
        #expect(PanelUndo.choose(fieldCanUndo: false, canUndoDelete: false) == .nothing)
    }
}
