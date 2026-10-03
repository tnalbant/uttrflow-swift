// Where each Core ML stage of the speech model runs, named so a harness can compare them.

/// The processors the recogniser's stages run on; the app ships `.shipping`. See Docs/speech-engines.md.
public enum SpeechComputePlan: String, Sendable, CaseIterable {
    /// Mel on CPU and GPU, encoder and decoder on CPU and Neural Engine.
    case shipping
    /// Every stage on CPU and GPU, leaving the Neural Engine idle.
    case gpu
    /// Every stage on CPU and Neural Engine.
    case neuralEngine
    /// Every stage on every processor Core ML chooses between.
    case all
    /// Every stage on the CPU alone, the floor every other plan is judged against.
    case cpu
}
