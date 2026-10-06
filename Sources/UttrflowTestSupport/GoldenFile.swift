// Recorded outputs per corpus case, so a change to the code shows every output it moved as a diff.
public import Foundation

/// One suite's recorded outputs in `Golden/<suite>.golden` beside its test, one `id<TAB>output` line per case.
public struct GoldenFile: Sendable {
    /// The environment variable that rewrites the file from the current outputs instead of comparing.
    public static let updateVariable = "UTTRFLOW_UPDATE_GOLDEN"

    /// Why a golden file could not be read or written.
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case refusedUnderCI
        case malformedLine(Int)

        public var description: String {
            switch self {
            case .refusedUnderCI:
                "\(GoldenFile.updateVariable) rewrites golden files locally only, never under CI"
            case .malformedLine(let line): "golden line \(line) has no tab between the case id and its output"
            }
        }
    }

    /// One case whose output no longer matches what was recorded.
    public struct Difference: Sendable, Equatable, CustomStringConvertible {
        public let id: String
        public let input: String
        public let recorded: String?
        public let actual: String?

        public var description: String {
            let recorded = recorded.map(GoldenFile.escape) ?? "<none>"
            let actual = actual.map(GoldenFile.escape) ?? "<none>"
            let input = GoldenFile.escape(input)
            return "\(id)\n  input:    \(input)\n  recorded: \(recorded)\n  actual:   \(actual)"
        }
    }

    /// Where this suite's outputs live.
    public let url: URL

    /// The golden file for `suite`, in the `Golden` folder beside the calling test file.
    public init(suite: String, testFile: StaticString = #filePath) {
        url = URL(fileURLWithPath: "\(testFile)").deletingLastPathComponent()
            .appendingPathComponent("Golden").appendingPathComponent("\(suite).golden")
    }

    /// A golden file at an exact location.
    public init(url: URL) {
        self.url = url
    }

    /// The recorded outputs by case id, or none when the file does not exist yet.
    public func recorded() throws -> [String: String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        return try Self.decode(text)
    }

    /// The cases whose output moved; with the update variable set it rewrites the file and reports none.
    public func compare(
        _ actual: [String: String], inputs: [String: String],
        environment: [String: String]? = nil
    ) throws -> [Difference] {
        let environment = environment ?? ProcessInfo.processInfo.environment
        if environment[Self.updateVariable] == "1" {
            guard environment["CI"] == nil else { throw Failure.refusedUnderCI }
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encode(actual).write(to: url, atomically: true, encoding: .utf8)
            return []
        }
        let recorded = try recorded()
        return Set(recorded.keys).union(actual.keys).sorted().compactMap { id in
            guard recorded[id] != actual[id] else { return nil }
            return Difference(id: id, input: inputs[id] ?? "", recorded: recorded[id], actual: actual[id])
        }
    }

    /// The file's text: lines sorted by case id, so a diff names only the cases that moved.
    public static func encode(_ outputs: [String: String]) -> String {
        outputs.keys.sorted().map { "\(escape($0))\t\(escape(outputs[$0] ?? ""))\n" }.joined()
    }

    /// The outputs by case id from a file's text.
    public static func decode(_ text: String) throws -> [String: String] {
        var outputs: [String: String] = [:]
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
            guard let tab = line.firstIndex(of: "\t") else { throw Failure.malformedLine(index + 1) }
            outputs[unescape(line[..<tab])] = unescape(line[line.index(after: tab)...])
        }
        return outputs
    }

    /// One line's worth of text, with the separators a line cannot hold written as escapes.
    public static func escape(_ text: String) -> String {
        var escaped = ""
        for character in text {
            switch character {
            case "\\": escaped += "\\\\"
            case "\n": escaped += "\\n"
            case "\t": escaped += "\\t"
            case "\r": escaped += "\\r"
            default: escaped.append(character)
            }
        }
        return escaped
    }

    /// The text an escaped line stands for.
    public static func unescape(_ text: Substring) -> String {
        var result = ""
        var pendingBackslash = false
        for character in text {
            if pendingBackslash {
                switch character {
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "r": result.append("\r")
                default: result.append(character)
                }
                pendingBackslash = false
            } else if character == "\\" {
                pendingBackslash = true
            } else {
                result.append(character)
            }
        }
        return result
    }
}
