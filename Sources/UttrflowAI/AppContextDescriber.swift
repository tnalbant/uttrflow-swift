// Describes the frontmost app for the prompt, from the destination the one table resolved.
public import UttrflowCore

/// Turns what the user is looking at into one prompt caption, or nil. See Docs/ai-context-line.md.
public enum AppContextDescriber {
    /// The label the prompt teaches the model to read as background.
    static let label = "Typed into:"
    /// The label the quoted screen text sits behind.
    static let selectionLabel = "nearby text:"

    /// The most window-title characters repeated; longer titles are paths and breadcrumbs.
    static let documentLimit = 60
    /// The most selection characters repeated; longer buys nothing measured. See Docs/ai-context-line.md.
    static let selectionLimit = 120

    /// The line to put above the dictation, or `nil` (never an empty string) when there is nothing to say.
    public static func describe(_ situation: Situation) -> String? {
        let context = situation.app
        let place = [placePhrase(situation), field(context.documentName, limit: documentLimit)]
            .compactMap { $0 }
            .joined(separator: ", ")
        let selection = field(context.selectedText, limit: selectionLimit)

        switch (place.isEmpty, selection) {
        case (true, nil):
            return nil
        case (true, let selection?):
            // A selection with no known place still uses the label the prompt teaches.
            return "\(label) an app; \(selectionLabel) \"\(selection)\""
        case (false, nil):
            return "\(label) \(place)"
        case (false, let selection?):
            return "\(label) \(place); \(selectionLabel) \"\(selection)\""
        }
    }

    // MARK: The place

    /// "a code editor (Xcode)", "a chat app", "an app called Linear", or nothing.
    private static func placePhrase(_ situation: Situation) -> String? {
        let name = field(situation.app.applicationName, limit: documentLimit)
        guard let kind = AppKind(naming: situation) else {
            // With no known kind the name is said as a noun phrase; a bare product name does nothing.
            return name.map { "an app called \($0)" }
        }
        guard let name else { return kind.phrase }
        return "\(kind.phrase) (\(name))"
    }

    // MARK: Sanitising

    /// The value as one safe prompt line cut to the limit, or nil when blank.
    static func field(_ value: String?, limit: Int) -> String? {
        guard let value else { return nil }
        let quoted = PromptText.quoted(value, limit: limit)
        return quoted.isEmpty ? nil : quoted
    }
}

extension AppKind {
    /// How the kind reads in the prompt, article included, because the line is a noun phrase.
    var phrase: String {
        switch self {
        case .chat: "a chat app"
        case .email: "an email app"
        case .codeEditor: "a code editor"
        case .terminal: "a terminal"
        case .sqlEditor: "a SQL editor"
        case .spreadsheet: "a spreadsheet"
        case .notes: "a note taking app"
        case .documentEditor: "a document editor"
        }
    }
}
