import Foundation
import Testing

@testable import UttrflowCore

private struct MockAccessibilityField {
    let selectedTextRange: CFRange?
    let selectedTextRanges: [CFRange]?

    var selection: AccessibilitySelection {
        AccessibilitySelection.resolve(
            singular: selectedTextRange, plural: selectedTextRanges, textLength: 20)
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

    @Test("A range outside the reported text is unavailable.")
    func rejectsRangesOutsideText() {
        let hostile = [
            CFRange(location: -1, length: 0),
            CFRange(location: 6, length: 0),
            CFRange(location: 4, length: 2),
            CFRange(location: NSNotFound, length: 0),
            CFRange(location: Int.max - 1, length: 2),
            CFRange(location: 2, length: -1),
        ]

        for range in hostile {
            guard
                case .unavailable = AccessibilitySelection.resolve(
                    singular: range, plural: nil, textLength: 5)
            else {
                Issue.record("An invalid range must not be exposed to consumers.")
                continue
            }
        }
    }

    @Test("A range within the reported text remains available.")
    func acceptsRangeWithinText() {
        guard
            case .range(let range) = AccessibilitySelection.resolve(
                singular: CFRange(location: 2, length: 3), plural: nil, textLength: 5)
        else {
            Issue.record("A valid selection must remain usable.")
            return
        }
        #expect(range.location == 2 && range.length == 3)
    }

    @Test("A range without a text length cannot be validated.")
    func rejectsRangeWithoutTextLength() {
        guard
            case .unavailable = AccessibilitySelection.resolve(
                singular: CFRange(location: 2, length: 0), plural: nil, textLength: nil)
        else {
            Issue.record("A selection without a known text boundary must remain unavailable.")
            return
        }
    }
}
