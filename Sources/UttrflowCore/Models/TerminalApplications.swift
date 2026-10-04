/// The applications whose text areas hold commands rather than prose, which Accessibility cannot tell by role alone.
public enum TerminalApplications {
    /// Lowercased bundle-identifier prefixes, so one entry covers a vendor's whole family.
    public static let bundleIdentifierPrefixes = DestinationRules.bundlePrefixes(of: [.terminal])

    /// Whether this application is a terminal, matched on a lowercased prefix since macOS is inconsistent about case.
    public static func contains(_ bundleIdentifier: String) -> Bool {
        let identifier = ApplicationKey.of(bundleIdentifier)
        return bundleIdentifierPrefixes.contains(where: identifier.hasPrefix)
    }
}
