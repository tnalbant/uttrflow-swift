import Testing

@testable import UttrflowContext

struct FieldNamesTests {
    private static func names(role: String? = "AXTextField", placeholder: String? = nil) -> FieldNames {
        FieldNames(role: role, subrole: nil, identifier: nil, placeholder: placeholder, description: nil)
    }

    @Test func declaredSecureFieldIsSecureWithoutItsValueBeingRead() {
        var asked = false
        let secure = Self.names(role: "AXSecureTextField").isSecure(value: {
            asked = true
            return "plain"
        })
        #expect(secure)
        #expect(!asked)
    }

    @Test func fieldNamedForASecretIsDeclaredSecure() {
        #expect(Self.names(placeholder: "Password").isDeclaredSecure)
    }

    @Test func undeclaredFieldIsSecureOnlyWhenItsValueIsMaskCharacters() {
        #expect(Self.names().isSecure(value: { "•••••" }))
        #expect(!Self.names().isSecure(value: { "hello" }))
        #expect(!Self.names().isSecure(value: { nil }))
    }
}
