// Tests that a dictation missing a piece of speech says so on the dock and to VoiceOver.
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline

@Suite("Missed speech in the dock and announcement")
struct MissedSpeechPresentationTests {
    private static let words = "Send the draft to the team before noon."

    private static func outcome(
        missed: Int, method: TextInsertionMethod = .typed, arrival: InsertionArrival = .confirmed,
        secure: Bool = false
    ) -> DictationState {
        .inserted(
            DictationOutcome(
                text: words, method: method, cleanedBy: .rules, arrival: arrival,
                intoSecureField: secure, missedPieces: missed))
    }

    @Test("the dock says part was not transcribed only when a piece is missing", arguments: [0, 1, 3])
    func dock(missed: Int) {
        let shown = DictationPresenter.dock(for: Self.outcome(missed: missed))
        if missed > 0 {
            #expect(shown.symbolName == "exclamationmark.circle")
            #expect(shown.primaryLine == MissedSpeech.line)
            #expect(shown.secondaryLine == MissedSpeech.detail)
            #expect(shown.accessibilityLabel.contains(MissedSpeech.sentence))
            #expect(shown.accessibilityLabel.contains(Self.words))
        } else {
            #expect(shown.symbolName == "checkmark")
            #expect(shown.primaryLine == "Inserted")
            #expect(!shown.accessibilityLabel.contains(MissedSpeech.sentence))
        }
    }

    @Test("VoiceOver hears the missing part only when a piece is missing", arguments: [0, 1, 3])
    func announcement(missed: Int) throws {
        let said = try #require(DictationPresenter.announcement(for: Self.outcome(missed: missed)))
        #expect(said.text.contains(MissedSpeech.sentence) == (missed > 0))
        #expect(!said.isUrgent)
    }

    @Test("copied and unconfirmed outcomes keep their instruction and add the missing part")
    func otherOutcomesCarryIt() throws {
        for state in [
            Self.outcome(missed: 2, method: .clipboard),
            Self.outcome(missed: 2, arrival: .unconfirmed),
        ] {
            let shown = DictationPresenter.dock(for: state)
            #expect(shown.primaryLine != MissedSpeech.line, "\(state)")
            #expect(shown.accessibilityLabel.contains(MissedSpeech.sentence), "\(state)")
            let said = try #require(DictationPresenter.announcement(for: state))
            #expect(said.text.contains(MissedSpeech.sentence), "\(state)")
        }
    }

    @Test("a secure field says part is missing without reading the words")
    func secureField() {
        let shown = DictationPresenter.dock(for: Self.outcome(missed: 1, secure: true))
        #expect(shown.primaryLine == MissedSpeech.line)
        #expect(shown.accessibilityLabel.contains(MissedSpeech.sentence))
        #expect(!shown.accessibilityLabel.contains(Self.words))
    }
}
