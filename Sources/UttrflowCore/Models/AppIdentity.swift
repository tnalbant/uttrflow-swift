/// Which application a dictation went to, the only half of an ``AppContext`` that may be stored.
public struct AppIdentity: Sendable, Equatable, Codable {
    /// Localised name of the application, e.g. `"Slack"`.
    public let applicationName: String?
    /// Bundle identifier of the application, e.g. `"com.tinyspeck.slackmacgap"`.
    public let bundleIdentifier: String?

    /// An identity; anything not supplied is unknown.
    public init(applicationName: String? = nil, bundleIdentifier: String? = nil) {
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
    }
}

extension AppContext {
    /// The storable half of this context, carrying none of the field's text or its window title.
    public var identity: AppIdentity {
        AppIdentity(applicationName: applicationName, bundleIdentifier: bundleIdentifier)
    }

    /// A context that knows only which application it is.
    public init(identity: AppIdentity) {
        self.init(applicationName: identity.applicationName, bundleIdentifier: identity.bundleIdentifier)
    }
}
