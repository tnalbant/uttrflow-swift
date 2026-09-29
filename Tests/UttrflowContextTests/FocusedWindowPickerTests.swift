import CoreGraphics
import Testing

@testable import UttrflowContext

@Suite("App-owned pickers in the focused window")
struct FocusedWindowPickerTests {
    private let field = CGRect(x: 300, y: 500, width: 400, height: 40)

    @Test(
        "a visible list, listbox or menu beside the focused field is a picker",
        arguments: [
            "AXList", "AXListBox", "AXMenu",
        ])
    func nearbyPopupRoleIsDetected(role: String) {
        let popup = Node(
            id: 2, role: role, frame: CGRect(x: 310, y: 250, width: 320, height: 220))
        let window = Node(id: 0, role: "AXWindow", children: [Node(id: 1, children: [popup])])

        #expect(FocusedWindowPicker.isOpen(in: window, near: field, using: FakeTree(root: window)))
    }

    @Test("a list elsewhere in the window or a hidden popup does not silence ordinary text")
    func unrelatedOrHiddenPopupIsIgnored() {
        let sidebar = Node(id: 2, role: "AXList", frame: CGRect(x: 10, y: 300, width: 180, height: 250))
        let hidden = Node(
            id: 3, role: "AXMenu", visible: false,
            frame: CGRect(x: 310, y: 250, width: 320, height: 220))
        let window = Node(id: 0, role: "AXWindow", children: [sidebar, hidden])

        #expect(!FocusedWindowPicker.isOpen(in: window, near: field, using: FakeTree(root: window)))
        #expect(!FocusedWindowPicker.isOpen(in: window, near: nil, using: FakeTree(root: window)))
    }
}
