/// Words said before a number that say how to write it, read from `number-cues.json`.
public enum NumberCues {
    /// What a cue word says about the number after it.
    public enum Cue: String, Decodable, Sendable {
        /// Digit groups a spoken "dot" joins are an address, version or decimal.
        case dotted
        /// A run of digit words is a code or a number to dial, not a count.
        case digitRun
    }

    /// The cue words that say `cue`.
    public static func words(for cue: Cue) -> Set<String> {
        Set(table.rows.filter { $0.cues.contains(cue) }.map(\.id))
    }

    /// The bundled table; see `Docs/data-tables.md`.
    static let table = DataTable<Row>.load("number-cues", schema: 1, from: .module, fallback: [])

    /// One cue word and what it says.
    struct Row: DataTableRow {
        let id: String
        let cues: Set<Cue>
    }
}
