/// The user's settings profile: the languages they speak, and nothing is uploaded.
public struct UserProfile: Sendable, Equatable, Codable {
    /// Languages in order of preference; the first is the routing fallback.
    public var preferredLanguages: [LanguageCode]

    /// A profile; it defaults to knowing nothing but English.
    public init(preferredLanguages: [LanguageCode] = [.english]) {
        self.preferredLanguages = preferredLanguages
    }

    /// The profile a user has before they configure anything.
    public static let `default` = UserProfile()
}

extension UserProfile {
    /// Keeps readable languages when neighbouring saved values cannot be decoded; keys it does not know are ignored.
    public init(from decoder: any Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            self = .default
            return
        }
        self.init(
            preferredLanguages: (try? container.decode(
                [ReadableSetting<LanguageCode>].self, forKey: .preferredLanguages))?
                .compactMap(\.value) ?? Self.default.preferredLanguages)
    }
}
