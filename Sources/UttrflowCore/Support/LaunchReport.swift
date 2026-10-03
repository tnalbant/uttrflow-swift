/// One launch's time to the dictation shortcut, as the line the app logs and `uttrflow-dev launch` reads.
public struct LaunchReport: Equatable, Sendable {
    /// Whether the first attempt to arm the shortcut succeeded; a refusal still ends the launch's wait.
    public enum Outcome: String, Sendable, CaseIterable {
        case armed
        case refused
    }

    /// Milliseconds from process start to the outcome, or `nil` when the start time was not known.
    public let milliseconds: Int?
    public let outcome: Outcome

    public init(age: Duration?, outcome: Outcome) {
        milliseconds = age.map { Int($0 / .milliseconds(1)) }
        self.outcome = outcome
    }

    /// The logged sentence, which says "unknown" rather than a number when the start time is missing.
    public var logged: String {
        let elapsed = milliseconds.map(String.init) ?? Self.unknown
        return "\(Self.lead) \(outcome.rawValue) \(elapsed) \(Self.tail)"
    }

    /// Finds a report anywhere in a log line, whatever the log tool printed in front of it.
    public init?(in text: String) {
        let words = text.split(separator: " ").map(String.init)
        let tail = Self.tail.split(separator: " ").map(String.init)
        for index in words.indices where words[index] == Self.lead {
            let rest = Array(words[(index + 1)...])
            guard rest.count == 2 + tail.count, Array(rest[2...]) == tail,
                let outcome = Outcome(rawValue: rest[0])
            else { continue }
            if rest[1] == Self.unknown {
                self.init(milliseconds: nil, outcome: outcome)
                return
            }
            guard let milliseconds = Int(rest[1]), milliseconds >= 0 else { continue }
            self.init(milliseconds: milliseconds, outcome: outcome)
            return
        }
        return nil
    }

    private init(milliseconds: Int?, outcome: Outcome) {
        self.milliseconds = milliseconds
        self.outcome = outcome
    }

    private static let lead = "shortcut"
    private static let tail = "ms after process start"
    private static let unknown = "unknown"
}
