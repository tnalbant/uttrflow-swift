public import CoreGraphics

/// Finds an app-owned picker in the window that contains the focused field.
public enum FocusedWindowPicker {
    /// Popup roles that identify a list of choices rather than a field's collapsed control.
    static let popupRoles: Set<String> = ["AXList", "AXListBox", "AXMenu"]

    /// How far a popup may sit above or below its field while still belonging to it.
    static let verticalReach: CGFloat = 500

    /// Whether a visible popup near the focused field appears anywhere under its own window.
    public static func isOpen<Tree: ElementTree>(
        in window: Tree.Element,
        near field: CGRect?,
        using tree: Tree,
        while shouldContinue: () -> Bool = { true }
    ) -> Bool {
        guard let field, !field.isEmpty else { return false }
        let nearbyField = field.insetBy(dx: -16, dy: -verticalReach)
        var pending = [window]
        var visited = 0
        while let element = pending.popLast(), visited < maximumElements, shouldContinue() {
            visited += 1
            if !tree.isHidden(element), popupRoles.contains(tree.role(of: element) ?? ""),
                let frame = tree.frame(of: element), !frame.isEmpty,
                nearbyField.intersects(frame)
            {
                return true
            }
            pending.append(contentsOf: tree.children(of: element))
        }
        return false
    }

    /// Bounds an app's Accessibility tree walk inside one focused-field read.
    public static let maximumElements = 100
}
