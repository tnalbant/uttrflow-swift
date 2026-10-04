# Measurement claims

Evidence behind rules 7 to 10 in
[code-quality.md](agents/code-quality.md#measurements-and-thresholds).

- **Clock start and stop, per sub-stage.** A published wait was taken from a harness whose clock
  stopped at "words ready" rather than at insertion, so it left out the tidy and insert stages.
  `StoredStageTiming` in `Sources/UttrflowEval/TranscriptionScore.swift` is where per-stage
  timings are recorded; a claim quotes those stages, not only the total.
- **Artefact read first.** A proposal to reuse a prompt-prefix cache across recordings was filed
  without reading that the cached state depends on the audio, and a field observer reported
  missing already exists in `Sources/UttrflowPredictCapture/CommitDetector.swift`.
- **Derived constants name their source.** `noSpeechThreshold` in
  `Sources/UttrflowSpeech/VocabularyPrompt.swift` is a fixed value with no recorded corpus or
  language; a threshold fitted on English speech is then applied to Hindi and Hinglish.
- **One current table.** A page that keeps several runs side by side leaves a reader to guess
  which one is true of the tree today.
