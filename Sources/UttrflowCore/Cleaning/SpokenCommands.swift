/// Which side of its name a spoken mark goes, which is what decides where a mention of it could stand.
public enum SpokenMarkKind: String, Decodable, Sendable, Equatable {
    /// Goes on the word before it: a comma, a full stop, a question mark.
    case trailing
    /// Joins the words on both sides of it: a hyphen, a dash.
    case joining
    /// Opens a quotation, so it goes on the word after it and needs nothing before it.
    case opening
    /// Closes one, so it goes on the word before it as a trailing mark does.
    case closing
}

/// One phrase said as an instruction rather than as words, and what it writes.
public struct SpokenCommand: DataTableRow, Equatable {
    /// What a command does with the words around it, which picks the pass that reads it.
    public enum Action: String, Decodable, Sendable {
        /// A punctuation mark written onto a neighbouring word.
        case mark
        /// A line break, paragraph break or list item.
        case layout
        /// A symbol written in place of its name in executable code.
        case codeSymbol
        /// A case style, named by `text`, applied to the words that follow in executable code.
        case casing
    }

    /// The row's stable name.
    public let id: String
    /// The spoken phrase, as lower-cased word keys.
    public let words: [String]
    /// What the command does.
    public let action: Action
    /// The text it writes.
    public let text: String
    /// Where a mark goes relative to its name; trailing when the row does not say.
    public let placement: SpokenMarkKind
    /// Whether the command writes a list item, so it applies only where lists are laid out.
    public let requiresLists: Bool
    /// The destinations it is enabled in; nil means every destination.
    public let destinations: Set<Destination>?

    /// Whether the command is enabled where the words are going.
    public func isEnabled(in destination: Destination) -> Bool {
        destinations?.contains(destination) ?? true
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        id = try container.decode(String.self, forKey: .id)
        words = try container.decode([String].self, forKey: .words)
        action = try container.decode(Action.self, forKey: .action)
        text = try container.decode(String.self, forKey: .text)
        placement = try container.decodeIfPresent(SpokenMarkKind.self, forKey: .placement) ?? .trailing
        requiresLists = try container.decodeIfPresent(Bool.self, forKey: .requiresLists) ?? false
        destinations = try container.decodeIfPresent(Set<Destination>.self, forKey: .destinations)
    }

    private enum Key: String, CodingKey {
        case id, words, action, text, placement, requiresLists, destinations
    }
}

/// Every spoken command, read from `spoken-commands.json`; a new command is a row there.
public enum SpokenCommands {
    /// The bundled rows; with none loaded every phrase stays as spoken.
    static let table = DataTable<SpokenCommand>.load(
        "spoken-commands", schema: 1, from: .module, fallback: [])

    /// Every row, in file order.
    public static var all: [SpokenCommand] { table.rows }
    /// Punctuation said by name, in file order so a longer name is tried before a shorter one.
    public static let marks = rows(.mark)
    /// Layout said by name.
    public static let layout = rows(.layout)
    /// Symbols said by name in code.
    public static let codeSymbols = rows(.codeSymbol)
    /// Case styles said by name in code.
    public static let casings = rows(.casing)
    /// The marks that open a quotation.
    public static let openings = marks.filter { $0.placement == .opening }
    /// The marks that close a quotation.
    public static let closings = marks.filter { $0.placement == .closing }

    private static func rows(_ action: SpokenCommand.Action) -> [SpokenCommand] {
        table.rows.filter { $0.action == action }
    }
}
