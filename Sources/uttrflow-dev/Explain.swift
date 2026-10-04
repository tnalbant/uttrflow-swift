// The `explain` command: replays a recorded clip and prints what each stage decided.
import ArgumentParser
import Foundation
import UttrflowAI
import UttrflowAudio
import UttrflowCore
import UttrflowSpeech

/// Transcribes and tidies one recorded clip, printing what every stage decided to the terminal only.
struct Explain: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Replay a recorded clip and show what each stage of dictation decided."
    )

    @Argument(help: "A recorded clip to replay, e.g. one made with `uttrflow-dev record`.")
    var file: String

    @Option(name: .shortAndLong, help: "Bias towards a language, e.g. en or hi. Omit to detect.")
    var language: String?

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    @OptionGroup var modelsDirectory: ModelsDirectoryOptionGroup

    func validate() throws {
        if let language, LanguageCode(language) == nil {
            throw ValidationError("'\(language)' is not a language code.")
        }
    }

    func run() async throws {
        let model = try resolve(modelVariant)
        let store = try modelsDirectory.store()
        guard store.isInstalled(model) else {
            throw CleanExit.message("\(model.variant) is not installed. Run: uttrflow-dev models install")
        }
        let audio = try AudioFileReader.read(contentsOf: URL(fileURLWithPath: file))
        guard !audio.isEmpty else { throw CleanExit.message("The file holds no audio.") }

        let speech = SpeechEngineFactory.make(
            kind: .whisperKit, model: model, modelFolder: store.location(of: model))
        try await speech.prepare()
        let transcription = try await speech.transcribe(
            audio, options: TranscriptionOptions(languageHint: language.flatMap(LanguageCode.init)))
        guard !transcription.isBlank else { throw CleanExit.message("Nothing was recognised.") }

        let explanation = try await DictationExplanation.tracing(
            TransformationRequest(transcription: transcription), through: TextTransformers.router())
        for line in explanation.lines { print("  \(line)") }
    }
}
