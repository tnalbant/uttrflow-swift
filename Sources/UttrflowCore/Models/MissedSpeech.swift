// The one wording every surface uses when part of a dictation decoded to no words.

/// What the dock, the menu bar and VoiceOver say about speech missing from an inserted dictation.
public enum MissedSpeech {
    /// The short headline, sized for the dock and the menu bar status line.
    public static let line = "Inserted — part not transcribed"
    /// The second line under the headline, saying what the person should check.
    public static let detail = "Part of what you said is missing"
    /// The full sentence read aloud, which never abbreviates.
    public static let sentence = "Part of what you said could not be transcribed and is missing."

    /// Whether a count of missed pieces means the text is incomplete.
    public static func isMissing(_ missedPieces: Int) -> Bool { missedPieces > 0 }
}
