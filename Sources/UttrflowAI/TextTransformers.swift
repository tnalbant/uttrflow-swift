public import UttrflowCore
public import UttrflowDictionary

/// Builds the transformers a build contains and the router over them; the one place naming concrete engines.
public enum TextTransformers {
    /// Every transformer in this build, running the steps the user left on; `spellings` is their dictionary.
    public static func all(
        steps: CleaningSteps = .default, spellings: (@Sendable () async -> PhoneticIndex)? = nil
    ) -> [any TextTransformationEngine] {
        let doubtful = spellings.map { DoubtfulWords.including(dictionary: $0) } ?? .standard
        return [
            GenerativeTextTransformer(
                kind: .foundationModels, model: AppleFoundationCleanupModel(),
                steps: steps, doubtful: doubtful),
            RuleBasedTransformer(steps: steps),
        ]
    }

    /// A router over every engine in this build, ordered by the configuration, with short replies left to the rules.
    public static func router(
        configuration: EngineConfiguration = .default, steps: CleaningSteps = .default,
        spellings: (@Sendable () async -> PhoneticIndex)? = nil
    ) -> TransformerRouter {
        TransformerRouter(
            engines: all(steps: steps, spellings: spellings),
            configuration: configuration, rulesAlone: .shortReplies, cleaningSteps: steps)
    }
}
