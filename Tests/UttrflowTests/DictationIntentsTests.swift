import Testing
import UttrflowPipeline

@testable import Uttrflow

@MainActor
@Suite("Dictation Shortcuts")
struct DictationIntentsTests {
    private func recordingCommands(_ body: () async throws -> Void) async rethrows -> [DictationCommand] {
        let previous = DictationIntentBridge.run
        var commands: [DictationCommand] = []
        DictationIntentBridge.run = { command in
            commands.append(command)
            return .nothingRecording
        }
        defer { DictationIntentBridge.run = previous }
        try await body()
        return commands
    }

    @Test("each intent sends its own command and nothing else")
    func intentsSendTheirCommand() async throws {
        let commands = try await recordingCommands {
            _ = try await ToggleDictationIntent().perform()
            _ = try await StartDictationIntent().perform()
            _ = try await StopDictationIntent().perform()
            _ = try await CancelDictationIntent().perform()
        }
        #expect(commands == [.toggle, .start, .stop, .cancel])
    }

    @Test("every outcome has its own spoken answer")
    func everyOutcomeIsSpokenDistinctly() {
        let outcomes: [DictationCommandOutcome] = [
            .started, .finished, .cancelled, .alreadyRecording, .nothingRecording, .didNotStart,
        ]
        let spoken = outcomes.map(DictationIntentBridge.spoken)
        #expect(Set(spoken).count == outcomes.count)
        #expect(DictationIntentBridge.spoken(.nothingRecording) == "Nothing was recording")
        #expect(DictationIntentBridge.spoken(.started) == "Listening")
    }
}
