import Foundation

/// Whether the caret sits inside a prose comment rather than executable code. See `Docs/cleanup-design.md`.
public enum CodeCommentContext {
    /// Whether the caret's own line opens a line comment, or an earlier block/doc comment is still unclosed.
    public static func isComment(precedingText: String?, documentName: String?) -> Bool {
        guard let precedingText, let markers = markers(for: documentName) else { return false }
        return isOnCommentLine(precedingText, linePrefixes: markers.line)
            || isInsideOpenBlockComment(precedingText, linePrefixes: markers.line, block: markers.block)
    }

    private struct Markers {
        let line: [String]
        let block: (open: String, close: String)?
    }

    /// The caret's own line, leading whitespace dropped, opens with a line-comment marker for this language.
    private static func isOnCommentLine(_ precedingText: String, linePrefixes: [String]) -> Bool {
        let line =
            precedingText.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).last ?? ""
        let trimmed = line.drop(while: \.isWhitespace)
        return linePrefixes.contains { trimmed.hasPrefix($0) }
    }

    /// Block-comment markers count only in code, outside strings and line comments.
    private static func isInsideOpenBlockComment(
        _ precedingText: String, linePrefixes: [String], block: (open: String, close: String)?
    ) -> Bool {
        guard let block else { return false }
        var depth = 0
        var index = precedingText.startIndex
        while index < precedingText.endIndex {
            if precedingText[index].isNewline {
                index = precedingText.index(after: index)
                continue
            }
            if linePrefixes.contains(where: { precedingText[index...].hasPrefix($0) }) {
                guard let newline = precedingText[index...].firstIndex(where: \.isNewline) else { break }
                index = precedingText.index(newline, offsetBy: 1)
                continue
            }
            switch Quoting.opening(in: precedingText, at: index, styles: QuoteStyle.sourceStrings) {
            case .closed(let end):
                index = end
                continue
            case .unclosed:
                return depth > 0
            case .none:
                break
            }
            if precedingText[index...].hasPrefix(block.open) {
                depth += 1
                index = precedingText.index(index, offsetBy: block.open.count)
            } else if depth > 0, precedingText[index...].hasPrefix(block.close) {
                depth -= 1
                index = precedingText.index(index, offsetBy: block.close.count)
            } else {
                index = precedingText.index(after: index)
            }
        }
        return depth > 0
    }

    /// The comment markers for a document's language, or `nil` for an unrecognised or untitled document.
    private static func markers(for documentName: String?) -> Markers? {
        guard let ext = fileExtension(from: documentName) else { return nil }
        switch ext {
        case "swift", "js", "jsx", "mjs", "cjs", "ts", "tsx", "java", "kt", "kts",
            "c", "h", "cc", "cpp", "cxx", "hpp", "m", "mm", "go", "rs", "cs", "php", "scala", "dart":
            return Markers(line: ["//"], block: ("/*", "*/"))
        case "py", "rb", "sh", "bash", "zsh", "fish", "yaml", "yml", "pl", "r":
            return Markers(line: ["#"], block: nil)
        case "sql":
            return Markers(line: ["--"], block: ("/*", "*/"))
        case "lua":
            return Markers(line: ["--"], block: ("--[[", "]]"))
        case "html", "htm", "xml":
            return Markers(line: [], block: ("<!--", "-->"))
        case "css", "scss", "less":
            return Markers(line: [], block: ("/*", "*/"))
        default:
            return nil
        }
    }

    /// The extension of the first filename-shaped token in a document name, which may carry a window title after it.
    private static func fileExtension(from documentName: String?) -> String? {
        guard let documentName else { return nil }
        for token in documentName.split(separator: " ") where token.contains(".") {
            guard let ext = token.split(separator: ".").last, !ext.isEmpty else { continue }
            return String(ext).lowercased()
        }
        return nil
    }
}
