// Decides which outcome cue, if any, a finished dictation earns.
public import UttrflowCore

/// The two outcome cues a dictation can end on.
public enum DictationOutcomeCue: Sendable, Equatable, CaseIterable {
    /// The words were seen to arrive where they were typed.
    case landed
    /// A failure that asks something of the user.
    case attention

    /// The cue `state` earns, by the same rule that allows the tick; `nil` when it earns none.
    public static func cue(for state: DictationState) -> DictationOutcomeCue? {
        switch state {
        case .inserted(let outcome)
        where outcome.method != .clipboard && !outcome.isFromRecording && outcome.arrival == .confirmed:
            return .landed
        case .failed(let failure) where failure.severity != .informational:
            return .attention
        default:
            return nil
        }
    }
}

/// Which outcome cues the user has switched on; each is read on every event, so a change applies at once.
public struct OutcomeCueSwitches: Sendable {
    let soundsEnabled: @Sendable () -> Bool
    let landedEnabled: @Sendable () -> Bool
    let attentionEnabled: @Sendable () -> Bool
    let voiceOverSpeaks: @Sendable () -> Bool

    /// Off unless switched on: both cues default to silent, and VoiceOver's announcement wins over either.
    public init(
        soundsEnabled: @escaping @Sendable () -> Bool,
        landedEnabled: @escaping @Sendable () -> Bool = { false },
        attentionEnabled: @escaping @Sendable () -> Bool = { false },
        voiceOverSpeaks: @escaping @Sendable () -> Bool
    ) {
        self.soundsEnabled = soundsEnabled
        self.landedEnabled = landedEnabled
        self.attentionEnabled = attentionEnabled
        self.voiceOverSpeaks = voiceOverSpeaks
    }

    func allows(_ cue: DictationOutcomeCue) -> Bool {
        // VoiceOver already announces every outcome that earns a cue, so the sound would talk over it.
        guard soundsEnabled(), !voiceOverSpeaks() else { return false }
        switch cue {
        case .landed: return landedEnabled()
        case .attention: return attentionEnabled()
        }
    }
}

/// Plays the outcome cue a state earns, once per arrival at that state.
public struct DictationOutcomeCueReporter: Sendable {
    private let cue: any OutcomeCueing
    private let switches: OutcomeCueSwitches

    public init(cue: any OutcomeCueing, switches: OutcomeCueSwitches) {
        self.cue = cue
        self.switches = switches
    }

    /// Called once on arriving at `state`; plays nothing for a state that earns no cue or is switched off.
    public func report(_ state: DictationState) {
        guard let earned = DictationOutcomeCue.cue(for: state), switches.allows(earned) else { return }
        switch earned {
        case .landed: cue.playLanded()
        case .attention: cue.playAttention()
        }
    }
}
