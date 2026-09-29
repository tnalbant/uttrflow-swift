public import CoreFoundation

/// A selection the Accessibility API reports as one range or as multiple independent ranges.
public enum AccessibilitySelection {
    /// A usable caret or selection, an ambiguous multi-range selection, or no reported range.
    case range(CFRange)
    case discontinuous
    case unavailable

    /// Prefers the plural attribute, and refuses to guess when it reports multiple ranges.
    public static func resolve(singular: CFRange?, plural: [CFRange]?) -> Self {
        if let plural, plural.count > 1 { return .discontinuous }
        if let range = plural?.first ?? singular { return .range(range) }
        return .unavailable
    }
}
