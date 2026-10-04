import Foundation

/// Produces a stable key for comparing text without regard to case or canonical Unicode spelling.
public enum TextMatching {
    /// Unicode case folding followed by canonical composition, preserving meaningful distinctions such as the dot on `İ`.
    public static func caseFoldedKey(_ text: String) -> String {
        text.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .precomposedStringWithCanonicalMapping
    }
}
