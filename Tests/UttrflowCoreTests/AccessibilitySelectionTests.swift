import Foundation
import Testing

@testable import UttrflowCore

private struct MockAccessibilityField {
    let selectedTextRange: CFRange?
    let selectedTextRanges: [CFRange]?

    var selection: AccessibilitySelection {
        AccessibilitySelection.resolve(singular: selectedTextRange, plural: selectedTextRanges)
    }
}

@Suite("Accessibility selections")
struct AccessibilitySelectionTests {
    @Test("A plural multi-range selection never falls back to the singular range.")
    func discontinuousSelectionRefusesStaleSingularRange() {
        let field = MockAccessibilityField(
            selectedTextRange: CFRange(location: 1, length: 0),
            selectedTextRanges: [CFRange(location: 1, length: 0), CFRange(location: 20, length: 0)])

        guard case .discontinuous = field.selection else {
            Issue.record("A field with multiple selected ranges must be unreadable.")
            return
        }
    }

    @Test("A single plural selection takes precedence over a stale singular range.")
    func singlePluralSelectionWins() {
        let field = MockAccessibilityField(
            selectedTextRange: CFRange(location: 1, length: 0),
            selectedTextRanges: [CFRange(location: 20, length: 0)])

        guard case .range(let range) = field.selection else {
            Issue.record("A single plural range must remain usable.")
            return
        }
        #expect(range.location == 20 && range.length == 0)
    }
}
