import Foundation
import Testing

@Suite("Account log privacy")
struct AccountLoggingAuditTests {
    @Test("logs account outcomes without carrying server messages or identity fields")
    func accountEventsUseFixedReasons() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/UttrflowAccount/HTTPAuthenticationService.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("category: \"account\""))
        #expect(source.contains("provider=\\(provider.rawValue"))
        #expect(source.contains("method=browser"))
        #expect(source.contains("method=code"))
        #expect(source.contains("sign-in: completed"))
        #expect(source.contains("session: profile refresh unchanged"))
        #expect(source.contains("session: profile refresh changed"))
        #expect(source.contains("session: profile refresh ended"))
        #expect(source.contains("sign-out: completed"))
        #expect(source.contains("case serverRefused"))
        #expect(!source.contains("answered?.message"))
        #expect(!source.contains("answered?.errorDescription"))
        #expect(!source.contains("account.emailAddress"))
        #expect(!source.contains("account.displayName"))
    }
}
