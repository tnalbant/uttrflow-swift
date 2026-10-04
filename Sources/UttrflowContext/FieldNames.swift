import UttrflowPredict

/// The five names a focused field publishes for itself, which the secure check reads before any of its text.
struct FieldNames: Sendable, Equatable {
    let role: String?
    let subrole: String?
    let identifier: String?
    let placeholder: String?
    let description: String?

    /// Whether the field declares itself secure, decided before its value is fetched.
    var isDeclaredSecure: Bool {
        SecureField.isDeclaredSecure(
            role: role, subrole: subrole, identifier: identifier, placeholder: placeholder,
            description: description)
    }

    /// The one secure-check order every focused-field read uses: the names first, the value only when they clear it.
    func isSecure(value: () -> String?) -> Bool {
        isDeclaredSecure || (value().map(SecureField.looksMasked) ?? false)
    }
}
