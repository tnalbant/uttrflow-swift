import Foundation
import OSLog
import UttrflowCore
import UttrflowPredict
import UttrflowPredictCapture

enum SuggestionConsentPersistence {
    private static let log = Logger(subsystem: "com.uttrflow.Uttrflow", category: "predict")

    @MainActor
    static func recordChanges(
        from before: SuggestionPreferences,
        to after: SuggestionPreferences,
        using capture: CaptureSession,
        onFailure: ((any Error) -> Void)?
    ) async {
        for application in after.turnedOff.subtracting(before.turnedOff) {
            await record(.declined, for: application, using: capture, onFailure: onFailure)
        }
        for application in after.turnedOn.subtracting(before.turnedOn) {
            await record(.allowed, for: application, using: capture, onFailure: onFailure)
        }
    }

    @MainActor
    private static func record(
        _ state: ConsentState,
        for application: String,
        using capture: CaptureSession,
        onFailure: ((any Error) -> Void)?
    ) async {
        do {
            try await capture.record(state, for: application)
        } catch {
            log.error(
                "could not save application consent: \(SuggestionLog.failure(error), privacy: .public)"
            )
            onFailure?(error)
        }
    }
}
