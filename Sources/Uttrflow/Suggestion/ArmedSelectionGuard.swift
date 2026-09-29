import Foundation
import UttrflowContext

/// Detects a moved caret or a different focused element while an offer is armed.
struct ArmedSelectionGuard {
    private(set) var expectedRange: NSRange?
    private var identity: (processIdentifier: Int32, elementHash: UInt)?

    init(expectedRange: NSRange?) {
        self.expectedRange = expectedRange
    }

    /// Answers whether the current Accessibility selection invalidates the offer.
    mutating func observe(_ selection: FocusedFieldSelection?) -> Bool {
        guard let selection, let expectedRange, selection.range == expectedRange else { return true }
        let currentIdentity = (selection.processIdentifier, selection.elementHash)
        if let identity,
            identity.processIdentifier != currentIdentity.0 || identity.elementHash != currentIdentity.1
        {
            return true
        }
        identity = currentIdentity
        return false
    }

    /// Advances the expected caret for text that the armed suggestion allows through.
    mutating func typedThrough(_ text: String) {
        guard let expectedRange else { return }
        self.expectedRange = NSRange(location: expectedRange.location + text.utf16.count, length: 0)
    }
}
