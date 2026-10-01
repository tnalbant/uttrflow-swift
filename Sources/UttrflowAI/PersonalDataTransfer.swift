// Validates and merges a local personal-data archive into the two stores.

public import UttrflowDictionary
public import struct Foundation.Data

public enum PersonalDataTransfer {
    /// Decodes and validates the complete input before either list is written.
    public static func importArchive(
        _ data: Data,
        into dictionary: PersonalDictionaryStore,
        and snippets: SnippetStore
    ) async throws -> PersonalDataMerge {
        let archive = try PersonalDataArchive.decode(data)
        guard
            archive.dictionary.allSatisfy({
                PhoneticIndex.supports(word: $0.word, pronunciation: $0.pronunciation)
            })
        else { throw PersonalDataArchiveError.invalidContents }

        let merged = archive.merging(
            dictionary: await dictionary.allEntries(), snippets: await snippets.snippets())
        let inferredCount = merged.dictionary.filter {
            $0.origin == .learned || $0.origin == .observed
        }.count
        guard inferredCount <= PersonalDictionaryStore.maximumInferredEntries else {
            throw PersonalDataTransferError.dictionaryCapacityExceeded
        }
        try await dictionary.replaceAll(merged.dictionary)
        try await snippets.replaceAll(merged.snippets)
        return merged
    }
}

public enum PersonalDataTransferError: Error, Sendable {
    case dictionaryCapacityExceeded
}
