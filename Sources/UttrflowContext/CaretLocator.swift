import CoreGraphics
import Foundation

/// Finds the caret's screen rectangle from whichever of a field's answers holds it. See `Docs/predict-reliability.md`.
enum CaretLocator {
    /// The caret at the selection, or at the text marker alone when the field refuses to say where its selection is; `frame` is the field's own.
    static func caret(
        at selection: (location: Int, length: Int)?, frame: CGRect?, pointSize: CGFloat? = nil,
        value: String? = nil, textSelectionLocation: Int? = nil,
        bounds: (_ location: Int, _ length: Int) -> CGRect?, markerBounds: () -> CGRect?
    ) -> CGRect? {
        if let selection,
            let rect = caret(
                inRange: selection, value: value,
                textSelectionLocation: textSelectionLocation ?? selection.location, bounds: bounds)
        {
            return rect
        }
        // A web field answers glyph bounds with a zero-size rectangle, but its selection's text-marker range still has a place on screen.
        if let rect = markerBounds(), isLine(rect, in: frame, pointSize: pointSize) {
            return CGRect(x: rect.minX, y: rect.minY, width: 0, height: rect.height)
        }
        // An editor that draws its own text keeps a one-pixel field at the caret for input methods, so that field's frame is the caret.
        if let frame, FocusedFieldSnapshot.isCaretShaped(frame) {
            return CGRect(x: frame.minX, y: frame.minY, width: 0, height: frame.height)
        }
        return nil
    }

    /// How many times the type size a line may stand, which leaves room for generous line spacing.
    static let linesPerPointSize: CGFloat = 3

    /// The tallest line where the field gives no type size, above any body or heading text.
    static let tallestLineWithoutType: CGFloat = 72

    /// Whether a text-marker rectangle is one line, not the whole field or a block of it, as a rich web editor answers.
    static func isLine(_ rect: CGRect, in frame: CGRect?, pointSize: CGFloat?) -> Bool {
        guard rect.height > 0 else { return false }
        if let frame, !FocusedFieldSnapshot.isCaretShaped(frame), isSame(rect, as: frame) { return false }
        let tallest = pointSize.map { $0 * linesPerPointSize } ?? tallestLineWithoutType
        return rect.height <= tallest
    }

    /// Whether two rectangles are the same to within a point on every edge.
    private static func isSame(_ rect: CGRect, as other: CGRect) -> Bool {
        abs(rect.minX - other.minX) <= 1 && abs(rect.minY - other.minY) <= 1
            && abs(rect.width - other.width) <= 1 && abs(rect.height - other.height) <= 1
    }

    /// The caret read off the glyph beside it, because a zero-length range's own bounds lies.
    private static func caret(
        inRange selection: (location: Int, length: Int), value: String?,
        textSelectionLocation: Int, bounds: (_ location: Int, _ length: Int) -> CGRect?
    ) -> CGRect? {
        if selection.length > 0 { return glyph(at: selection.location, bounds: bounds) }
        let location = selection.location
        // A line break's bounds belong to the line it ends, so use the first glyph on the next line.
        return glyph(
            at: location, value: value, textSelectionLocation: textSelectionLocation, bounds: bounds)
    }

    /// The caret edge beside a single glyph at the selection start.
    private static func glyph(
        at location: Int, value: String? = nil, textSelectionLocation: Int? = nil,
        bounds: (_ location: Int, _ length: Int) -> CGRect?
    ) -> CGRect? {
        let textLocation = textSelectionLocation ?? location
        let followsLineBreak = hasLineBreak(beforeUTF16Offset: textLocation, in: value)
        // The caret sits at the trailing edge of the complete character before it, including emoji graphemes.
        let precedingLength = precedingCharacterLength(in: value, beforeUTF16Offset: textLocation) ?? 1
        if location > 0, !followsLineBreak,
            let before = bounds(location - precedingLength, precedingLength), before.height > 0
        {
            return CGRect(x: before.maxX, y: before.minY, width: 0, height: before.height)
        }
        // At the start of the value, or just after a line break, use the following glyph.
        if let at = bounds(location, 1), at.height > 0 {
            return CGRect(x: at.minX, y: at.minY, width: 0, height: at.height)
        }
        return nil
    }

    /// The UTF-16 length of the complete character immediately before the caret.
    private static func precedingCharacterLength(in text: String?, beforeUTF16Offset offset: Int) -> Int? {
        guard let text, offset > 0 else { return nil }
        let utf16 = text.utf16
        guard offset <= utf16.count,
            let end = String.Index(utf16.index(utf16.startIndex, offsetBy: offset), within: text)
        else { return nil }
        let start = text.index(before: end)
        return text[start..<end].utf16.count
    }

    /// Whether the UTF-16 unit before the caret ends a line, matching Accessibility's selection offsets.
    private static func hasLineBreak(beforeUTF16Offset offset: Int, in value: String?) -> Bool {
        guard let value, offset > 0, offset <= value.utf16.count else { return false }
        let index = value.utf16.index(value.utf16.startIndex, offsetBy: offset - 1)
        return switch value.utf16[index] {
        case 0x0A, 0x0B, 0x0C, 0x0D, 0x85, 0x2028, 0x2029: true
        default: false
        }
    }
}
