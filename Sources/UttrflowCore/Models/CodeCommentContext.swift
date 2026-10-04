import Foundation

/// Whether the caret sits inside a prose comment rather than executable code. See `Docs/cleanup-design.md`.
public enum CodeCommentContext {
    /// Whether the caret, scanning the text before it as code, ends inside a line comment, block comment or docstring.
    public static func isComment(precedingText: String?, documentName: String?) -> Bool {
        guard let precedingText, let markers = markers(for: documentName) else { return false }
        return endsInsideComment(precedingText, markers: markers)
    }

    /// Whether the caret sits in executable source: a recognised language, outside any comment.
    public static func isCode(precedingText: String?, documentName: String?) -> Bool {
        guard let markers = markers(for: documentName) else { return false }
        return !(precedingText.map { endsInsideComment($0, markers: markers) } ?? false)
    }

    /// Whether the caret sits in the body prose of a Markdown or plain-text document: any line but a `#` heading.
    public static func isDocumentProse(precedingText: String?, documentName: String?) -> Bool {
        guard let ext = fileExtension(from: documentName), proseExtensions.contains(ext) else { return false }
        let caretLine = precedingText?.split(separator: "\n", omittingEmptySubsequences: false).last ?? ""
        return !caretLine.drop(while: { $0 == " " }).hasPrefix("#")
    }

    private static let proseExtensions: Set<String> = ["md", "markdown", "txt"]

    private struct Markers {
        let line: [String]
        let block: (open: String, close: String)?
        var docstrings: [QuoteStyle] = []
    }

    /// Python string delimiters that, left open, hold a docstring rather than a value.
    private static let pythonDocstrings: [QuoteStyle] = ["\"\"\"", "'''"].map {
        QuoteStyle(open: $0, close: $0, literal: .backslash, escapes: [:])
    }

    /// Comment markers count only in code, outside strings, so a marker after code on the caret's line opens a comment.
    private static func endsInsideComment(_ text: String, markers: Markers) -> Bool {
        var depth = 0
        var index = text.startIndex
        while index < text.endIndex {
            if depth > 0, let block = markers.block {
                if text[index...].hasPrefix(block.close) {
                    depth -= 1
                    index = text.index(index, offsetBy: block.close.count)
                } else if text[index...].hasPrefix(block.open) {
                    depth += 1
                    index = text.index(index, offsetBy: block.open.count)
                } else {
                    index = text.index(after: index)
                }
                continue
            }
            if markers.line.contains(where: { text[index...].hasPrefix($0) }) {
                guard let newline = text[index...].firstIndex(where: \.isNewline) else { return true }
                index = text.index(after: newline)
                continue
            }
            switch Quoting.opening(in: text, at: index, styles: markers.docstrings) {
            case .closed(let end):
                index = end
                continue
            case .unclosed:
                return true
            case .none:
                break
            }
            switch Quoting.opening(in: text, at: index, styles: QuoteStyle.sourceStrings) {
            case .closed(let end):
                index = end
                continue
            case .unclosed:
                return false
            case .none:
                break
            }
            if let block = markers.block, text[index...].hasPrefix(block.open) {
                depth += 1
                index = text.index(index, offsetBy: block.open.count)
            } else {
                index = text.index(after: index)
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
        case "py":
            return Markers(line: ["#"], block: nil, docstrings: pythonDocstrings)
        case "rb", "sh", "bash", "zsh", "fish", "yaml", "yml", "pl", "r":
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
