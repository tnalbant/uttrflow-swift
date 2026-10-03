// Tests that scrolling or losing the key window dismisses the row menu without changing its actions.

import Foundation
import Testing
import UttrflowUX

@testable import Uttrflow

@Suite("The quick panel's row menu dismissal")
struct QuickPanelMenuDismissalTests {
    @Test("a live scroll closes the open row menu")
    func scrollClosesMenu() {
        var menu = PanelRowMenuState()
        menu.open(UUID())

        menu.handle(.scroll)

        #expect(menu.rowID == nil)
    }

    @Test("losing key status closes the open row menu")
    func resigningKeyClosesMenu() {
        var menu = PanelRowMenuState()
        menu.open(UUID())

        menu.handle(.windowResignedKey)

        #expect(menu.rowID == nil)
    }

    @Test("selecting an action closes the menu and performs that action")
    func selectingActionPreservesAction() {
        let rowID = UUID()
        let action = PanelAction(title: "Copy", symbolName: "doc.on.doc", intent: .copy(rowID))
        var menu = PanelRowMenuState()
        menu.open(rowID)
        var performed: PanelIntent?

        menu.select(action) { performed = $0 }

        #expect(menu.rowID == nil)
        #expect(performed == .copy(rowID))
    }
}
