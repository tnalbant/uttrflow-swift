// Tests for UserProfile.

import Foundation
import Testing

@testable import UttrflowCore

@Suite("UserProfile")
struct UserProfileTests {
    @Test("defaults to English and nothing else")
    func defaultProfile() {
        #expect(UserProfile.default.preferredLanguages == [.english])
    }

    @Test("round-trips a populated profile through Codable")
    func codableRoundTrip() throws {
        let original = UserProfile(preferredLanguages: [.english, .hindi])
        let decoded = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    @Test("loads a profile saved with the retired self-reported fields and drops them on the next write")
    func retiredFieldsAreIgnored() throws {
        let saved = Data(
            #"""
            {"profession": "surgeon", "preferredLanguages": ["hi", "en"], "technicalDomains": ["SQL"],
             "preferredWritingStyle": "Concise", "vocabulary": ["Kubernetes"]}
            """#.utf8)
        let loaded = try JSONDecoder().decode(UserProfile.self, from: saved)
        #expect(loaded == UserProfile(preferredLanguages: [.hindi, .english]))

        let written = try JSONSerialization.jsonObject(with: JSONEncoder().encode(loaded)) as? [String: Any]
        #expect(written.map { Set($0.keys) } == ["preferredLanguages"])
    }
}
