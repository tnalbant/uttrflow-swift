/// What a click or a spoken intent asks of the dictation, stated outright so it cannot fall out of step.
public enum DictationCommand: Sendable, Equatable {
    case toggle
    case start
    case stop
    case cancel
}

/// What a `DictationCommand` did, judged against the state the gesture queue found.
public enum DictationCommandOutcome: Sendable, Equatable {
    case started
    case finished
    case cancelled
    case alreadyRecording
    case nothingRecording
    case didNotStart
}
