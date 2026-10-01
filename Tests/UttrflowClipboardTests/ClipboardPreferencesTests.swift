import Foundation
import Testing

@testable import UttrflowClipboard

@Suite("Clipboard privacy preferences")
struct ClipboardPreferencesTests {
    @Test("normalizes app IDs, preserves choices privately, and fails open for unknown provenance")
    func roundTripsExclusions() throws {
        var preferences = ClipboardPreferences()
        preferences.exclude("Com.Example.Secret")
        #expect(preferences.excludes("com.example.secret"))
        #expect(!preferences.excludes("com.example.other"))
        #expect(!preferences.excludes(nil))

        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = ClipboardPreferencesFile(
            path: ClipboardPreferencesFile.defaultFile(in: directory).path)
        try file.save(preferences)
        #expect(file.load() == preferences)

        preferences.include("COM.EXAMPLE.SECRET")
        #expect(preferences.excludedBundleIdentifiers.isEmpty)
    }
}
