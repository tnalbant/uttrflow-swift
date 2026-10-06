// The spellings people type for one romanised Hindi word, held once as data so every sound key reads the same sets.
/// The other spellings of each romanised Hindi word, read from `romanised-variants.json`; a spelling is added by adding it to its word's row.
public enum RomanisedVariants {
    /// The word a listed spelling is typed for ("bohot" is "bahut"), the word itself for its own row, or nil when the spelling is not listed.
    public static func word(of spelling: String) -> String? {
        wordsBySpelling[spelling]
    }

    /// The bundled table; see `Docs/data-tables.md`.
    static let table = DataTable<Row>.load("romanised-variants", schema: 1, from: .module, fallback: [])

    private static let wordsBySpelling = Dictionary(
        table.rows.flatMap { row in ([row.id] + row.variants).map { ($0, row.id) } },
        uniquingKeysWith: { first, _ in first })

    /// One word as it is most often typed, with the other spellings people type for it.
    public struct Row: DataTableRow {
        public let id: String
        public let variants: [String]
    }
}
