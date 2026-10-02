// The chords a row's actions answer to, in one table so the handler, the ⋯ menu and the docs agree.

/// A ⌘ chord, named by the character the key reports so a view can match a key press without a key code.
public struct PanelChord: Sendable, Equatable, Hashable {
    /// The character, lower-cased; AppKit reports Backspace as `\u{7F}`.
    public let character: Character
    /// Whether ⇧ is held as well as ⌘, which keeps a chord off the search field's own editing keys.
    public let isShifted: Bool

    public init(_ character: Character, shifted: Bool = false) {
        self.character = character
        self.isShifted = shifted
    }

    /// The chord as the user reads it, in the menu and in `Docs/shortcuts.md`.
    public var label: String {
        "⌘" + (isShifted ? "⇧" : "") + (character == "\u{7F}" ? "⌫" : character.uppercased())
    }
}

/// One thing a row offers, named without a clip, which is what a chord can be bound to.
public enum PanelRowAction: Sendable, Equatable, CaseIterable {
    case reveal
    case copy
    /// One action for both, because a row offers whichever of the two applies to it.
    case pin
    case alias
    case move
    case format
    case reindent
    case makeNote
    case delete
}

extension PanelRowAction {
    /// The chord that performs it: the one place any of them is written down.
    public var chord: PanelChord {
        switch self {
        case .reveal: PanelChord("r")
        // ⌘C is the search field's own copy, so the row's takes ⇧ as well.
        case .copy: PanelChord("c", shifted: true)
        case .pin: PanelChord("p")
        case .alias: PanelChord("n")
        case .move: PanelChord("m")
        case .format: PanelChord("f", shifted: true)
        case .reindent: PanelChord("i", shifted: true)
        case .makeNote: PanelChord("t", shifted: true)
        // ⌫ and ⌘⌫ edit the query, and a chord that acted only on an empty field would be a trap.
        case .delete: PanelChord("\u{7F}", shifted: true)
        }
    }
}

extension PanelPresentation {
    /// What a ⌘ chord does to the highlighted row, read off that row's own actions so the two agree.
    public func intent(for chord: PanelChord) -> PanelIntent? {
        selectedRow?.actions.first { $0.shortcut == chord }?.intent
    }
}
