/// Shared wording for features that are still in beta.
public enum BetaFeature {
    public static let label = "Beta"

    /// The feature name as VoiceOver reads it beside the visible beta badge.
    public static func accessibilityName(_ name: String) -> String {
        "\(name), beta"
    }
}
