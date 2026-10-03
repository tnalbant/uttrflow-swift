/// What the user is looking at when they dictate; every field is optional, macOS grants each conditionally.
public struct AppContext: Sendable, Equatable {
    /// Localised name of the frontmost application, e.g. `"Slack"`.
    public let applicationName: String?
    /// Bundle identifier of the frontmost application, e.g. `"com.tinyspeck.slackmacgap"`.
    public let bundleIdentifier: String?
    /// Title of the focused window or document, where the app exposes it.
    public let documentName: String?
    /// Text the user had selected, where readable. Never modified by the pipeline.
    public let selectedText: String?
    /// Up to ``InsertionPoint/precedingLimit`` characters before the caret; `nil` when the field will not say.
    public let precedingText: String?
    /// Up to ``InsertionPoint/followingLimit`` characters after the selection; `nil` when the field will not say.
    public let followingText: String?
    /// Whether the focused field hides what is typed, so none of its text is carried and nothing is kept.
    public let isSecure: Bool
    /// The focused field's Accessibility role, when the system reports one.
    public let accessibilityRole: String?
    /// Whether the focused field can hold multiple lines, when reported by Accessibility.
    public let isMultiline: Bool?

    /// A context; anything not supplied is unknown.
    public init(
        applicationName: String? = nil,
        bundleIdentifier: String? = nil,
        documentName: String? = nil,
        selectedText: String? = nil,
        precedingText: String? = nil,
        followingText: String? = nil,
        isSecure: Bool = false,
        accessibilityRole: String? = nil,
        isMultiline: Bool? = nil
    ) {
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.documentName = documentName
        self.selectedText = selectedText
        self.precedingText = precedingText
        self.followingText = followingText
        self.isSecure = isSecure
        self.accessibilityRole = accessibilityRole
        self.isMultiline = isMultiline
    }

    /// The context available when macOS tells us nothing.
    public static let unknown = AppContext()

    /// `true` when no field carries information, so a prompt can leave the context section out.
    public var isEmpty: Bool {
        applicationName == nil
            && bundleIdentifier == nil
            && documentName == nil
            && selectedText == nil
            && precedingText == nil
            && followingText == nil
    }
}

extension AppContext: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The application only, so a log line or interpolation never carries what the field holds.
    public var description: String {
        "AppContext(\(applicationName ?? "unknown app"), \(bundleIdentifier ?? "no bundle"), field text redacted)"
    }

    /// The same redacted line as ``description``.
    public var debugDescription: String { description }

    /// A mirror with the application only, so `dump` and debugger views cannot print field text.
    public var customMirror: Mirror {
        Mirror(self, children: ["identity": identity], displayStyle: .struct)
    }
}
