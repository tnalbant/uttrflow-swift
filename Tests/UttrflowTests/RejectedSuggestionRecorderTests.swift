import Testing
import UttrflowContext

@testable import Uttrflow

private enum RejectionWriteError: Error {
    case unavailable
}

private actor ThrowingRejectedStore: RejectedSuggestionStore {
    private(set) var attempts = 0

    func recordRejected(_ text: String, in surface: Surface) async throws {
        attempts += 1
        throw RejectionWriteError.unavailable
    }
}

@Suite("Rejected suggestion persistence")
struct RejectedSuggestionRecorderTests {
    @Test("A rejected line stays suppressed while its counter write fails and retries.")
    @MainActor
    func retriesFailedRejectionAndKeepsLineSuppressed() async {
        let surface = Surface(bundleIdentifier: "com.example.editor", role: "AXTextArea")
        let store = ThrowingRejectedStore()
        let recorder = RejectedSuggestionRecorder(store: store)

        await recorder.record("wrong completion", in: surface)
        #expect(await store.attempts == 1)
        #expect(recorder.suppresses("wrong completion", in: surface))
        #expect(
            !recorder.suppresses(
                "wrong completion", in: Surface(bundleIdentifier: "com.example.other", role: "AXTextArea")))

        await recorder.retry()
        #expect(await store.attempts == 2)
        #expect(recorder.suppresses("wrong completion", in: surface))
    }
}
