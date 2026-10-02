/// Checklist boxes in a note.
public enum NoteChecklist {
    /// One box, and whether it is ticked.
    public struct Item: Sendable, Equatable {
        public let isChecked: Bool

        public init(isChecked: Bool) {
            self.isChecked = isChecked
        }
    }

    /// The boxes in a note, in the order they are written.
    public static func items(in html: String) -> [Item] {
        marks(in: html).map { Item(isChecked: $0.isChecked) }
    }

    /// How much of a checklist is done, or `nil` when the note has no boxes.
    public static func progress(in html: String) -> (done: Int, total: Int)? {
        let found = marks(in: html)
        guard !found.isEmpty else { return nil }
        return (found.count { $0.isChecked }, found.count)
    }

    // MARK: - Finding the boxes

    /// Where a box is written and whether it is checked.
    private struct Mark {
        let range: Range<String.Index>
        let isChecked: Bool
    }

    /// The three spellings real pasteboards use, matched on whole tokens, as `unchecked` contains `checked`.
    private static func marks(in html: String) -> [Mark] {
        var found: [Mark] = []
        var index = html.startIndex

        while let open = html[index...].firstIndex(of: "<") {
            guard let close = html[open...].firstIndex(of: ">") else { break }
            index = html.index(after: close)
            if let mark = mark(of: String(html[open...close]), at: open..<index) {
                found.append(mark)
            }
        }
        return found
    }

    /// The box this tag is, or `nil` when it is not one.
    private static func mark(of tag: String, at range: Range<String.Index>) -> Mark? {
        let lower = tag.lowercased()
        let box = lower.hasPrefix("<input") ? inputBox(tag, lower) : listItemBox(tag, lower)
        return box.map { Mark(range: range, isChecked: $0) }
    }

    /// A real `<input type="checkbox">`, as GitHub writes one.
    private static func inputBox(_ tag: String, _ lower: String) -> Bool? {
        guard
            lower.contains("type=\"checkbox\"") || lower.contains("type='checkbox'")
                || lower.contains("type=checkbox")
        else { return nil }
        // A bare `checked` is the HTML spelling; `checked="checked"` is the XHTML one.
        let isChecked = hasAttribute("checked", in: lower)
        return isChecked
    }

    /// Whether the tag carries this attribute in its own right, so `aria-checked` is not read as `checked`.
    private static func hasAttribute(_ name: String, in lower: String) -> Bool {
        var searched = lower.startIndex
        while let found = lower.range(of: name, range: searched..<lower.endIndex) {
            searched = found.upperBound
            guard found.lowerBound > lower.startIndex,
                lower[lower.index(before: found.lowerBound)].isWhitespace
            else { continue }
            let after = found.upperBound == lower.endIndex ? ">" : lower[found.upperBound]
            if after == "=" || after == ">" || after == "/" || after.isWhitespace { return true }
        }
        return false
    }

    /// Apple Notes and TipTap mark the item rather than writing an input.
    private static func listItemBox(_ tag: String, _ lower: String) -> Bool? {
        guard lower.hasPrefix("<li") else { return nil }
        let classes = tokens(of: "class", in: lower)
        let isChecked = classes.contains("checked") || lower.contains("data-checked=\"true\"")

        return classes.contains("checked") || classes.contains("unchecked")
            || lower.contains("data-checked=\"true\"") || lower.contains("data-checked=\"false\"")
            ? isChecked
            : nil
    }

    /// The values of one attribute, split into whole words.
    private static func tokens(of attribute: String, in lower: String) -> [String] {
        guard let start = lower.range(of: "\(attribute)=\"") else { return [] }
        let rest = lower[start.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return [] }
        return rest[..<end].split(separator: " ").map(String.init)
    }

}

/// E6 — turning a plain clip into a note.
public enum NotePromotion {
    /// The note form of some plain text: line breaks become paragraphs, and nothing else is interpreted.
    public static func note(from text: String) -> String {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { "<p>" + escaped(String($0)) + "</p>" }
            .joined()
    }

    /// The five characters that would otherwise become markup when the note is read back.
    static func escaped(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "\'": out += "&#39;"
            default: out.append(character)
            }
        }
        return out
    }
}
