// Tests that no dictionary entry is ever stored with a Devanagari spelling.

import Foundation
import Testing
import UttrflowCore

@testable import UttrflowDictionary

@Suite("Keeping every dictionary spelling in Latin letters")
struct LatinScriptEntryTests {
    private let devanagari = "\u{0906}\u{0930}\u{0935}"

    @Test("a word typed in Devanagari is stored romanised, its Devanagari kept as the pronunciation")
    func typedInDevanagari() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        try await store.add(word: devanagari, pronunciation: "", at: epoch)

        let kept = try #require(await store.allEntries().first)
        #expect(kept.word == Romaniser.romanised(devanagari))
        #expect(!Romaniser.containsDevanagari(kept.word))
        #expect(kept.pronunciation == devanagari)
        #expect(sandbox.onDisk()?.contains { Romaniser.containsDevanagari($0.word) } == false)
    }

    @Test("a typed pronunciation is kept when the spelling is respelt")
    func typedPronunciationKept() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        try await store.add(word: devanagari, pronunciation: "aa rav", at: epoch)
        #expect(await store.allEntries().first?.pronunciation == "aa rav")
    }

    @Test("a Devanagari word and its romanised spelling are one entry")
    func duplicateAcrossScripts() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        try await store.add(word: Romaniser.romanised(devanagari), pronunciation: "", at: epoch)
        await #expect(throws: DictionaryStoreError.wordAlreadyKnown) {
            try await store.add(word: devanagari, pronunciation: "", at: epoch)
        }
    }

    @Test("an import never stores a Devanagari spelling")
    func importRespells() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        try await store.replaceAll { _ in
            ([word(devanagari, from: .added), word("Uttrflow", from: .added)], ())
        }
        let words = await store.allEntries().map(\.word)
        #expect(words == [Romaniser.romanised(devanagari), "Uttrflow"])
    }

    @Test("an entry already on disk in Devanagari is respelt once, answering each change before and after")
    func migration() async throws {
        let sandbox = Sandbox()
        let held = word(devanagari, from: .added)
        try PrivateFile.write(JSONEncoder().encode([held, word("Uttrflow", from: .added)]), to: sandbox.file)
        let store = PersonalDictionaryStore(file: sandbox.file)

        let changes = try await store.respellInLatinScript()
        #expect(changes.map(\.before) == [held])
        #expect(changes.map(\.after.word) == [Romaniser.romanised(devanagari)])
        #expect(changes.map(\.after.id) == [held.id])
        #expect(try await store.respellInLatinScript().isEmpty)
        #expect(await store.allEntries().contains { Romaniser.containsDevanagari($0.word) } == false)
    }

    @Test("a Latin entry is its own Latin form")
    func latinUnchanged() {
        let latin = word("Uttrflow", from: .added)
        #expect(latin.inLatinScript == latin)
    }
}
