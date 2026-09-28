// Tests that ⌘Z in the quick panel undoes typing, else restores a deleted clip, ahead of the main menu.

import AppKit
import Testing
import UttrflowUX

@testable import Uttrflow

/// A key-down for `character` with `modifiers` held, addressed to `window`.
@MainActor
private func key(
    _ character: String, _ modifiers: NSEvent.ModifierFlags, in window: NSWindow? = nil
) throws -> NSEvent {
    try #require(
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: window?.windowNumber ?? 0, context: nil, characters: character,
            charactersIgnoringModifiers: character, isARepeat: false, keyCode: 6))
}

/// A panel with an editable field in focus, as the search field is when the panel opens.
@MainActor
private struct Fixture {
    let panel: QuickPanel
    let field: FieldWithUndo

    init(canUndoDelete: Bool) {
        panel = QuickPanel(
            contentRect: CGRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.nonactivatingPanel], backing: .buffered, defer: true)
        field = FieldWithUndo(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        field.allowsUndo = true
        panel.contentView = field
        panel.makeFirstResponder(field)
        panel.canUndoDelete = { canUndoDelete }
    }
}

/// A text view whose undo history the test owns, as the panel's field editor owns its own.
private final class FieldWithUndo: NSTextView {
    private let history = UndoManager()
    override var undoManager: UndoManager? { history }
}

@MainActor
@Suite("⌘Z in the quick panel")
struct QuickPanelUndoTests {
    @Test("⌘Z alone is the undo key; ⇧⌘Z and a plain z are not")
    func recognisesUndo() throws {
        #expect(QuickPanel.isUndo(try key("z", .command)))
        #expect(!QuickPanel.isUndo(try key("z", [.command, .shift])))
        #expect(!QuickPanel.isUndo(try key("z", [])))
        #expect(!QuickPanel.isUndo(try key("z", [.command, .option])))
    }

    @Test("typing in the focused field is undone, and a deleted clip stays deleted")
    func undoesTyping() throws {
        let fixture = Fixture(canUndoDelete: true)
        var restored = 0
        fixture.panel.onUndoDelete = { restored += 1 }
        fixture.field.insertText("abc", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(fixture.field.string == "abc")

        #expect(fixture.panel.performKeyEquivalent(with: try key("z", .command, in: fixture.panel)))
        #expect(fixture.field.string == "")
        #expect(restored == 0)
    }

    @Test("with no typing to undo, ⌘Z restores the deleted clip")
    func restoresTheDelete() throws {
        let fixture = Fixture(canUndoDelete: true)
        var restored = 0
        fixture.panel.onUndoDelete = { restored += 1 }

        #expect(fixture.panel.performKeyEquivalent(with: try key("z", .command, in: fixture.panel)))
        #expect(restored == 1)
    }

    @Test("with neither, ⌘Z does nothing and still keeps it from the menu")
    func doesNothing() throws {
        let fixture = Fixture(canUndoDelete: false)
        var restored = 0
        fixture.panel.onUndoDelete = { restored += 1 }

        #expect(fixture.panel.performKeyEquivalent(with: try key("z", .command, in: fixture.panel)))
        #expect(restored == 0)
        #expect(fixture.field.string == "")
    }

    @Test("the controller sends Undo Delete when the app says a delete can be undone")
    func controllerRoutesTheDelete() throws {
        let controller = QuickPanelController()
        var sent: [PanelIntent] = []
        controller.onIntent = { intent, _ in sent.append(intent) }
        controller.canUndoDelete = { true }
        let panel = try #require(Mirror(reflecting: controller).descendant("panel") as? QuickPanel)
        panel.makeFirstResponder(nil)

        #expect(panel.performKeyEquivalent(with: try key("z", .command, in: panel)))
        #expect(sent == [.undoDelete])
    }
}
