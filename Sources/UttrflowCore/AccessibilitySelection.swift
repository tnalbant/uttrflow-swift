public import CoreFoundation
import Foundation

/// A selection the Accessibility API reports as one range or as multiple independent ranges.
public enum AccessibilitySelection {
    /// A usable caret or selection, an ambiguous multi-range selection, or no reported range.
    case range(CFRange)
    case discontinuous
    case unavailable

    /// Prefers the plural attribute, refuses multiple ranges, and rejects invalid UTF-16 bounds.
    public static func resolve(
        singular: CFRange?, plural: [CFRange]?, textLength: Int?
    ) -> Self {
        if let plural, plural.count > 1 { return .discontinuous }
        guard let range = plural?.first ?? singular, let textLength, textLength >= 0,
            range.location != NSNotFound, range.location >= 0, range.length >= 0
        else { return .unavailable }
        let (end, overflow) = range.location.addingReportingOverflow(range.length)
        guard !overflow, end <= textLength else {
            return .unavailable
        }
        return .range(range)
    }
}
