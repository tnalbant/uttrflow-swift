// Attested romanised spellings of one Hindi word, held once as data so every judge of "one word" reads the same sets.
/// The spelling sets read from `romanised-variants.json`; a variant is added by adding it to its word's row.
enum RomanisedVariants {
    /// The word's most common spelling when the word is listed, otherwise nil; `spelling` is matched lowercased.
    static func canonical(of spelling: String) -> String? {
        canonicalBySpelling[spelling.lowercased()]
    }

    /// The bundled table; see `Docs/data-tables.md`.
    static let table = DataTable<Row>.load("romanised-variants", schema: 1, from: .module, fallback: [])

    private static let canonicalBySpelling: [String: String] = Dictionary(
        table.rows.flatMap { row in ([row.id] + row.variants).map { ($0, row.id) } },
        uniquingKeysWith: { first, _ in first })

    /// One Hindi word as it is most often typed, with the other spellings people type for it.
    struct Row: DataTableRow {
        let id: String
        let variants: [String]
    }
}
