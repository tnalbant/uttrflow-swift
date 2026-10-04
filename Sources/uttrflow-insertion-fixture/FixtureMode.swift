// The ways a fixture field misbehaves on purpose, each one a defect `Docs/insertion.md` records.
import Foundation

/// How words reached a fixture field: written through Accessibility, or sent as keys (typed or pasted).
enum FixtureRoute {
    case accessibility
    case keys
}

/// What a fixture field holds after an edit, and where its caret ends.
struct FixtureEdit: Equatable {
    let text: String
    let caret: Int
}

/// One fault a fixture field shows, chosen on its command line.
enum FixtureMode: String, CaseIterable {
    /// Takes every edit as given; the baseline the faults are measured against.
    case faithful
    /// Answers an Accessibility write with success and changes nothing.
    case changesNothing = "changes-nothing"
    /// Never receives posted keys, as a paste sent to a tap the target never hears.
    case dropsKeys = "drops-keys"
    /// Rewrites quotes and double hyphens as it takes the words.
    case substitutes
    /// Keeps no more than `lengthCap` characters.
    case capsLength = "caps-length"

    /// The most characters a `capsLength` field keeps.
    static let lengthCap = 16

    /// The field after `incoming` replaces `range` (UTF-16) of `current`, or nil when the field keeps what it had.
    func edit(
        _ current: String, replacing range: NSRange, with incoming: String, by route: FixtureRoute
    )
        -> FixtureEdit?
    {
        switch (self, route) {
        case (.changesNothing, .accessibility), (.dropsKeys, .keys): return nil
        default: break
        }
        let written = self == .substitutes ? Self.substituted(incoming) : incoming
        let whole = current as NSString
        let bounded = NSIntersectionRange(range, NSRange(location: 0, length: whole.length))
        let replaced = whole.replacingCharacters(in: bounded, with: written)
        let caret = bounded.location + (written as NSString).length
        guard self == .capsLength, replaced.count > Self.lengthCap else {
            return FixtureEdit(text: replaced, caret: caret)
        }
        let kept = String(replaced.prefix(Self.lengthCap))
        return FixtureEdit(text: kept, caret: min(caret, (kept as NSString).length))
    }

    /// Curly apostrophes, alternating curly double quotes, and an em dash for `--`.
    static func substituted(_ text: String) -> String {
        var opening = true
        var result = ""
        for character in text.replacingOccurrences(of: "--", with: "\u{2014}") {
            switch character {
            case "'": result.append("\u{2019}")
            case "\"":
                result.append(opening ? "\u{201C}" : "\u{201D}")
                opening.toggle()
            default: result.append(character)
            }
        }
        return result
    }
}
