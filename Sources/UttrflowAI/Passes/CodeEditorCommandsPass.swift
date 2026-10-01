public import UttrflowCore

/// Writes spoken identifier and symbol commands in executable code.
public struct CodeEditorCommandsPass: CleaningPass {
    public static let id: PassID = .codeEditorCommands

    public init() {}

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        var position = 0
        while position < draft.presentIndices.count {
            let live = draft.presentIndices
            guard position < live.count else { break }
            if let command = Self.casing(at: position, in: live, of: draft) {
                apply(command, at: position, in: live, to: &draft)
                position += 1
            } else if let symbol = Self.symbol(at: position, in: live, of: draft) {
                apply(symbol, at: position, in: live, to: &draft)
                position += 1
            } else {
                position += 1
            }
        }
        return draft
    }

    private enum Command {
        case casing(style: CaseStyle, consumed: Int, wordCount: Int)
        case symbol(text: String, consumed: Int)
    }

    private enum CaseStyle {
        case camel, snake, kebab, upper
    }

    private static func casing(at position: Int, in live: [Int], of draft: Draft) -> Command? {
        guard position + 1 < live.count else { return nil }
        let first = draft.shape(at: live[position]).key
        let second = draft.shape(at: live[position + 1]).key
        let style: CaseStyle
        switch (first, second) {
        case ("camel", "case"): style = .camel
        case ("snake", "case"): style = .snake
        case ("kebab", "case"): style = .kebab
        case ("all", "caps"): style = .upper
        default: return nil
        }
        var end = position + 2
        var wordCount = 0
        while end < live.count {
            let shape = draft.shape(at: live[end])
            if isSpokenClauseWord(shape) { break }
            wordCount += 1
            end += 1
            if shape.endsClause || WordShape.trailsOff(shape.suffix) { break }
        }
        guard wordCount > 0 else { return nil }
        return .casing(style: style, consumed: wordCount + 2, wordCount: wordCount)
    }

    private static func symbol(at position: Int, in live: [Int], of draft: Draft) -> Command? {
        let key = draft.shape(at: live[position]).key
        if position + 1 < live.count {
            let next = draft.shape(at: live[position + 1]).key
            if key == "open", ["paren", "parenthesis"].contains(next) {
                return .symbol(text: "(", consumed: 2)
            }
            if key == "close", ["paren", "parenthesis"].contains(next) {
                return .symbol(text: ")", consumed: 2)
            }
            if key == "open", next == "bracket" { return .symbol(text: "[", consumed: 2) }
            if key == "close", next == "bracket" { return .symbol(text: "]", consumed: 2) }
            if key == "open", next == "brace" { return .symbol(text: "{", consumed: 2) }
            if key == "close", next == "brace" { return .symbol(text: "}", consumed: 2) }
        }
        let symbols: [String: String] = [
            "equals": "=", "arrow": "->", "dot": ".", "underscore": "_",
            "colon": ":", "semicolon": ";", "comma": ",",
        ]
        guard let text = symbols[key] else { return nil }
        return .symbol(text: text, consumed: 1)
    }

    private static func isSpokenClauseWord(_ shape: WordShape) -> Bool {
        ["comma", "period", "colon", "semicolon"].contains(shape.key)
    }

    private func apply(_ command: Command, at position: Int, in live: [Int], to draft: inout Draft) {
        switch command {
        case .casing(let style, let consumed, let wordCount):
            let spoken = (position + 2)..<(position + 2 + wordCount)
            let values = spoken.map { draft.shape(at: live[$0]).core }
            let suffix = draft.shape(at: live[position + consumed - 1]).suffix
            let converted: String
            switch style {
            case .camel:
                converted = values.enumerated().map { index, value in
                    index == 0 ? value.lowercased() : WordShape.capitalised(value.lowercased())
                }.joined()
            case .snake: converted = values.map { $0.lowercased() }.joined(separator: "_")
            case .kebab: converted = values.map { $0.lowercased() }.joined(separator: "-")
            case .upper: converted = values.map { $0.uppercased() }.joined(separator: " ")
            }
            draft.replace(at: live[position], with: converted + suffix, by: Self.id)
            for offset in 1..<consumed { draft.remove(at: live[position + offset], by: Self.id) }
        case .symbol(let text, let consumed):
            let suffix = draft.shape(at: live[position + consumed - 1]).suffix
            if text == ")", position > 0, draft.words[live[position - 1]].text == "(" {
                draft.replace(at: live[position - 1], with: "()" + suffix, by: Self.id)
                for offset in 0..<consumed { draft.remove(at: live[position + offset], by: Self.id) }
                return
            }
            draft.replace(at: live[position], with: text + suffix, by: Self.id)
            for offset in 1..<consumed { draft.remove(at: live[position + offset], by: Self.id) }
        }
    }
}
