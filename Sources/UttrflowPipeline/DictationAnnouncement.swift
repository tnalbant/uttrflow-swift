// What VoiceOver says when a dictation starts, lands or fails.
import UttrflowCore

/// One sentence for VoiceOver to speak unasked, since the floating button never takes focus.
public struct DictationAnnouncement: Sendable, Equatable {
    /// What is spoken; a glance at the words, never the whole dictation.
    public let text: String
    /// Whether it interrupts what VoiceOver is reading, which only a failure earns.
    public let isUrgent: Bool

    public init(text: String, isUrgent: Bool) {
        self.text = text
        self.isUrgent = isUrgent
    }
}

extension DictationPresenter {
    /// What to announce on arriving at `state`, or `nil` when the state is not news.
    public static func announcement(for state: DictationState) -> DictationAnnouncement? {
        switch state {
        // The wait is covered by the stop cue, and announcing it would talk over the result.
        case .idle, .transcribing, .tidying, .inserting:
            return nil

        case .recording:
            return DictationAnnouncement(text: "Listening.", isUrgent: false)

        case .inserted(let outcome) where outcome.method == .clipboard && outcome.isFromRecording:
            return DictationAnnouncement(
                text: "Copied to the clipboard. Press Command V to paste it. \(preview(of: said(outcome)))",
                isUrgent: false)

        case .inserted(let outcome) where outcome.method == .clipboard:
            return DictationAnnouncement(
                text: "Copied to the clipboard, not typed. Press Command V to paste it. "
                    + "Uttrflow needs Accessibility access to type for you.",
                isUrgent: true)

        case .inserted(let outcome) where outcome.arrival == .unconfirmed:
            return DictationAnnouncement(
                text: "Inserted, but not confirmed. Press Command V if the words are missing.",
                isUrgent: false)

        case .inserted(let outcome):
            return DictationAnnouncement(text: "Inserted: \(preview(of: said(outcome)))", isUrgent: false)

        case .failed(let failure):
            let message = failure.message.filter { $0 != "…" }
            guard let recovery = failure.recovery else {
                return DictationAnnouncement(text: message, isUrgent: true)
            }
            return DictationAnnouncement(
                text: "\(message) \(recovery.instruction)", isUrgent: true)
        }
    }
}

private extension RecoveryAction {
    /// Where VoiceOver users can reach the recovery offered on the floating button.
    var instruction: String {
        switch self {
        case .openSystemSettings:
            "Open Settings from the Uttrflow menu."
        case .retry:
            "Choose Try Again from the Uttrflow menu."
        case .downloadSpeechModel:
            "Choose Download from the Uttrflow menu."
        case .pasteManually:
            "The text is on your clipboard. Press Command V to paste it."
        case .showRecentDictations:
            "Open Recent from the Uttrflow menu to find your words."
        case .retryFromRecording:
            "Open History from the Uttrflow menu, then choose Retry on the recording."
        }
    }
}
