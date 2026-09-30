// How the verification tier retires a candidate, which is the corpus's supersession under another name.
public import UttrflowPredict

extension PredictStore: SupersessionRecording {
    /// Marks a candidate wrong for the verification tier, throwing when it cannot be retired.
    public func recordSupersession(of text: String, by replacement: String, in surface: Surface) throws {
        try supersede(text, with: replacement, in: surface)
    }

    /// Marks a refused candidate as its own successor, throwing when the refusal cannot be stored.
    public func recordRejection(of text: String, in surface: Surface) throws {
        try supersede(text, with: text, in: surface)
    }
}
