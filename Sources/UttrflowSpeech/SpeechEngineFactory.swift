// The one switch that names a concrete recogniser.
public import Foundation
public import UttrflowCore

/// Builds the speech engine named by the configuration; nothing else mentions a concrete recogniser.
public enum SpeechEngineFactory {
    /// Builds the configured recogniser from an installed `modelFolder`.
    public static func make(
        kind: SpeechEngineKind,
        model: SpeechModel = .default,
        modelFolder: URL,
        prewarm: Bool = true,  // Only a measurement harness passes false; see Docs/performance-dictation.md.
        idleAfter: Duration? = nil,
        didRelease: (@Sendable () -> Void)? = nil,
        didLoad: (@Sendable () -> Void)? = nil,
        willLoad: (@Sendable () -> Void)? = nil
    ) -> BackedSpeechEngine {
        switch kind {
        case .whisperKit:
            BackedSpeechEngine(
                kind: .whisperKit,
                backend: WhisperKitBackend(model: model, modelFolder: modelFolder, prewarm: prewarm),
                idleAfter: idleAfter,
                didRelease: didRelease,
                didLoad: didLoad,
                willLoad: willLoad
            )
        case .appleSpeech:
            BackedSpeechEngine(
                kind: .appleSpeech, backend: AppleSpeechBackend(), idleAfter: idleAfter,
                didRelease: didRelease, didLoad: didLoad, willLoad: willLoad)
        }
    }
}
