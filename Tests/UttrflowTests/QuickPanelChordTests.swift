// Tests that the quick panel takes its row chords ahead of the main menu, so ⌘M moves a clip.

import AppKit
import Testing
import UttrflowUX

@testable import Uttrflow

/// A view that records the keys the window hands it.
private final class KeyRecorder: NSView {
    var keys: [String] = []
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { keys.append(event.charactersIgnoringModifiers ?? "") }
}

/// A key-down for `characters` at `keyCode` with `modifiers` held, addressed to `window`.
@MainActor
private func key(
    _ characters: String, _ modifiers: NSEvent.ModifierFlags,
    keyCode: UInt16? = nil, in window: NSWindow? = nil
) throws -> NSEvent {
    let code = keyCode ?? characters.first.flatMap { PanelChord($0).keyCode } ?? 0
    return try #require(
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: window?.windowNumber ?? 0, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
}

@MainActor
@Suite("The quick panel's row chords")
struct QuickPanelChordTests {
    @Test("every row chord is recognised, with ⇧ where the chord takes it")
    func recognisesRowChords() throws {
        let examples: [(PanelRowAction, String, UInt16)] = [
            (.reveal, "к", 15), (.copy, "с", 8), (.pin, "з", 35),
            (.alias, "т", 45), (.move, "ь", 46), (.format, "а", 3),
            (.reindent, "ш", 34), (.makeNote, "е", 17), (.delete, "\u{7F}", 51),
        ]
        for (action, producedCharacter, code) in examples {
            let event = try key(
                producedCharacter, action.chord.isShifted ? [.command, .shift] : .command,
                keyCode: code)
            #expect(QuickPanel.rowChord(event) == action.chord, action.chord.label)
        }
    }

    @Test("keys that are not row chords are left to the menu and the field")
    func leavesOtherKeysAlone() throws {
        #expect(!QuickPanel.isRowChord(try key("ь", [], keyCode: 46)))
        #expect(!QuickPanel.isRowChord(try key("w", .command)))
        #expect(!QuickPanel.isRowChord(try key("я", .command, keyCode: 6)))
        #expect(!QuickPanel.isRowChord(try key("с", .command, keyCode: 8)))
        #expect(!QuickPanel.isRowChord(try key("ь", [.command, .option], keyCode: 46)))
        #expect(!QuickPanel.isRowChord(try key("ь", [.command, .control], keyCode: 46)))
    }

    /// Window ▸ Minimise is ⌘M, and the menu swallows it even where it is disabled.
    @Test("Move's chord is one the Window menu also binds")
    func moveSharesMinimiseKey() throws {
        let minimise = try #require(MainMenu.window.items.first { $0.title == "Minimise" })
        #expect(minimise.keyEquivalent == String(PanelRowAction.move.chord.character))
        #expect(minimise.keyEquivalentModifierMask == .command)
        #expect(!PanelRowAction.move.chord.isShifted)
    }

    @Test("a Cyrillic-produced physical ⌘M reaches the row action before the menu")
    func commandMReachesThePanel() throws {
        let panel = QuickPanel(
            contentRect: CGRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.nonactivatingPanel], backing: .buffered, defer: true)
        let recorder = KeyRecorder()
        panel.contentView = recorder
        panel.makeFirstResponder(recorder)
        var received: PanelChord?
        panel.onRowChord = { received = $0 }

        #expect(panel.performKeyEquivalent(with: try key("ь", .command, keyCode: 46, in: panel)))
        #expect(received == PanelRowAction.move.chord)
        #expect(recorder.keys.isEmpty)
    }

    @Test("a key that is not a row chord is not claimed")
    func otherKeysAreNotClaimed() throws {
        let panel = QuickPanel(
            contentRect: CGRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.nonactivatingPanel], backing: .buffered, defer: true)
        let recorder = KeyRecorder()
        panel.contentView = recorder
        panel.makeFirstResponder(recorder)

        #expect(!panel.performKeyEquivalent(with: try key("w", .command, in: panel)))
        #expect(recorder.keys.isEmpty)
    }

    @Test("⌘Z restores a clip while the offer shows, and otherwise only when the field has no typing to undo")
    func undoGoesToTheOfferThenTheField() throws {
        let undo = try key("я", .command, keyCode: 6)

        #expect(QuickPanel.claimsUndo(undo, offersRestore: true, fieldCanUndo: true))
        #expect(QuickPanel.claimsUndo(undo, offersRestore: true, fieldCanUndo: false))
        #expect(QuickPanel.claimsUndo(undo, offersRestore: false, fieldCanUndo: false))
        #expect(!QuickPanel.claimsUndo(undo, offersRestore: false, fieldCanUndo: true))
    }

    @Test("Redo and other chords are never taken as the restore")
    func redoIsLeftAlone() throws {
        #expect(
            !QuickPanel.claimsUndo(
                try key("Я", [.command, .shift], keyCode: 6),
                offersRestore: true, fieldCanUndo: false))
        #expect(
            !QuickPanel.claimsUndo(
                try key("я", [.command, .option], keyCode: 6),
                offersRestore: true, fieldCanUndo: false))
        #expect(
            !QuickPanel.claimsUndo(try key("я", [], keyCode: 6), offersRestore: true, fieldCanUndo: false))
        #expect(
            !QuickPanel.claimsUndo(
                try key("ч", .command, keyCode: 7), offersRestore: true, fieldCanUndo: false))
    }

    @Test("a Cyrillic-produced physical ⌘Z restores ahead of Edit › Undo")
    func commandZReachesThePanel() throws {
        let panel = QuickPanel(
            contentRect: CGRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.nonactivatingPanel], backing: .buffered, defer: true)
        let recorder = KeyRecorder()
        panel.contentView = recorder
        panel.makeFirstResponder(recorder)
        panel.offersRestore = true
        var restored = false
        panel.onUndo = { restored = true }

        #expect(panel.performKeyEquivalent(with: try key("я", .command, keyCode: 6, in: panel)))
        #expect(restored)
        #expect(recorder.keys.isEmpty)
    }
}
