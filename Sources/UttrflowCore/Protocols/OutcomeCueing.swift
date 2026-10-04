/// The sounds that say how a dictation ended; in Core so the pipeline never depends on how they play.
public protocol OutcomeCueing: Sendable {
    /// Plays the cue that the words were seen to reach the caret.
    func playLanded()
    /// Plays the cue that a dictation failed and asks something of the user.
    func playAttention()
}

/// Plays nothing, which is every outcome cue until a sound is chosen for it.
public struct SilentOutcomeCue: OutcomeCueing {
    /// A cue with nothing to set up.
    public init() {}
    /// Plays nothing.
    public func playLanded() {}
    /// Plays nothing.
    public func playAttention() {}
}
