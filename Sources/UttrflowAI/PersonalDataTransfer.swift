// Validates and merges a local personal-data archive into the two stores.

public import UttrflowDictionary
public import struct Foundation.Data

public enum PersonalDataTransfer {
    /// Validates the whole archive, then merges each list inside its store; a failed second write undoes the first.
    public static func importArchive(
        _ data: Data,
        into dictionary: PersonalDictionaryStore,
        and snippets: SnippetStore
    ) async throws -> PersonalDataImportReport {
        let archive = try PersonalDataArchive.decode(data)
        guard
            archive.dictionary.allSatisfy({
                PhoneticIndex.supports(word: $0.word, pronunciation: $0.pronunciation)
            })
        else { throw PersonalDataArchiveError.invalidContents }

        // Snippets go first because their merge only appends, so removing what it added is an exact undo.
        let snippetMerge = try await snippets.replaceAll { current in
            let merge = archive.mergedSnippets(into: current)
            return (merge.records, merge)
        }
        let words: (kept: [DictionaryEntry], outcome: PersonalDataMerge<DictionaryEntry>)
        do {
            words = try await dictionary.replaceAll { current in
                let merge = archive.mergedDictionary(into: current)
                return (merge.records, merge)
            }
        } catch {
            let added = Set(snippetMerge.added.map(\.id))
            try? await snippets.replaceAll { current in (current.filter { !added.contains($0.id) }, ()) }
            throw error
        }
        return PersonalDataImportReport(
            duplicateWords: words.outcome.duplicates, duplicateSnippets: snippetMerge.duplicates,
            skippedInferredWords: words.outcome.records.count - words.kept.count)
    }
}

/// What an import skipped: duplicates, and the weakest inferred words beyond the store's bound.
public struct PersonalDataImportReport: Sendable, Equatable {
    public let duplicateWords: Int
    public let duplicateSnippets: Int
    public let skippedInferredWords: Int
}
