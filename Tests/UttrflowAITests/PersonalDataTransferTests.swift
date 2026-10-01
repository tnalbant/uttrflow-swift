import Foundation
import Testing
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowAI

@Suite("Personal data import")
struct PersonalDataTransferTests {
    @Test("refuses a malformed archive before changing either store")
    func malformedArchiveDoesNotWrite() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "uttrflow-personal-data-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let dictionary = PersonalDictionaryStore(file: root.appending(path: "dictionary.json"))
        let snippets = SnippetStore(file: root.appending(path: "snippets.json"))
        try await dictionary.add(
            DictionaryEntry(word: "Uttrflow", origin: .added, firstSeen: .distantPast))
        try await snippets.save(
            Snippet(trigger: "my address", expansion: "42 Example Road", created: .distantPast))
        let wordsBefore = await dictionary.allEntries()
        let snippetsBefore = await snippets.snippets()

        do {
            _ = try await PersonalDataTransfer.importArchive(
                Data("not a personal-data archive".utf8), into: dictionary, and: snippets)
            Issue.record("malformed archive was accepted")
        } catch {}

        #expect(await dictionary.allEntries() == wordsBefore)
        #expect(await snippets.snippets() == snippetsBefore)
    }

    @Test("valid imports merge once and return duplicate counts")
    func importsAndReportsDuplicates() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "uttrflow-personal-data-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let dictionary = PersonalDictionaryStore(file: root.appending(path: "dictionary.json"))
        let snippets = SnippetStore(file: root.appending(path: "snippets.json"))
        let knownWord = DictionaryEntry(word: "Uttrflow", origin: .added, firstSeen: .distantPast)
        let newWord = DictionaryEntry(word: "Kubernetes", origin: .added, firstSeen: .distantPast)
        let knownSnippet = Snippet(
            trigger: "my address", expansion: "Existing", created: .distantPast)
        let newSnippet = Snippet(
            trigger: "my email", expansion: "a@example.com", created: .distantPast)
        try await dictionary.add(knownWord)
        try await snippets.save(knownSnippet)
        let bytes = try PersonalDataArchive(
            dictionary: [
                DictionaryEntry(word: "uttrflow", origin: .learned, firstSeen: .distantPast), newWord,
            ],
            snippets: [
                Snippet(trigger: "MY address", expansion: "Imported", created: .distantPast), newSnippet,
            ]
        ).encoded()

        let result = try await PersonalDataTransfer.importArchive(
            bytes, into: dictionary, and: snippets)
        #expect(result.duplicateWords == 1)
        #expect(result.duplicateSnippets == 1)
        #expect(await dictionary.allEntries() == [knownWord, newWord])
        #expect(await snippets.snippets() == [knownSnippet, newSnippet])
    }

    @Test("rejects an import over the inferred-word limit before either store changes")
    func refusesOverLimitWithoutWriting() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "uttrflow-personal-data-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let dictionary = PersonalDictionaryStore(file: root.appending(path: "dictionary.json"))
        let snippets = SnippetStore(file: root.appending(path: "snippets.json"))
        let entries = (0...PersonalDictionaryStore.maximumInferredEntries).map { index in
            DictionaryEntry(
                word: "word\(index)", origin: .observed, firstSeen: .distantPast)
        }
        let archive = try PersonalDataArchive(dictionary: entries, snippets: []).encoded()

        do {
            _ = try await PersonalDataTransfer.importArchive(
                archive, into: dictionary, and: snippets)
            Issue.record("over-limit archive was accepted")
        } catch PersonalDataTransferError.dictionaryCapacityExceeded {
            #expect(await dictionary.allEntries().isEmpty)
            #expect(await snippets.snippets().isEmpty)
        } catch {
            Issue.record("unexpected import error: \(error)")
        }
    }
}
