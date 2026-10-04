import UttrflowPredict

/// The five names a focused field publishes for itself, which the secure check reads before any of its text.
public struct FieldNames: Sendable, Equatable {
    public let role: String?
    public let subrole: String?
    public let identifier: String?
    public let placeholder: String?
    public let description: String?

    /// Whether the field declares itself secure, decided before its value is fetched.
    public var isDeclaredSecure: Bool {
        SecureField.isDeclaredSecure(
            role: role, subrole: subrole, identifier: identifier, placeholder: placeholder,
            description: description)
    }

    /// The one secure-check order every focused-field read uses: the names first, the value only when they clear it.
    public func isSecure(value: () -> String?) -> Bool {
        isDeclaredSecure || (value().map(SecureField.looksMasked) ?? false)
    }
}
