// The `synthesise` command: fills a corpus with the system synthesiser reading the English passages.
import ArgumentParser
private import Foundation
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval

/// Writes a repeatable corpus that needs no microphone, for comparing recognisers on one Mac.
struct SynthesiseCorpus: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "synthesise",
        abstract: "Have the system synthesiser read the English passages into a corpus."
    )

    @Option(name: .long, help: "Where the synthesised corpus is written; keep it apart from a recorded one.")
    var corpusPath: String

    @Option(name: .long, help: "The `say` voice that reads every passage.")
    var voice = "Samantha"

    func run() async throws {
        let resolved = resolveVoice(requested: voice, catalogue: SayVoiceCatalogue())
        guard let installed = resolved.installed else {
            throw CleanExit.message("Voice '\(voice)' is not installed; `say -v ?` lists those that are.")
        }
        let store = TranscriptionCorpusStore(directory: URL(fileURLWithPath: corpusPath))
        let cohort = RecordingCohort(
            id: "synthesised-\(installed.lowercased())", speaker: installed, setting: "say, 16 kHz")
        // English only: a Latin-script voice reading Hindi measures the synthesiser, not the recogniser.
        let passages = store.remaining().filter { $0.language == .english }
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("uttrflow-say.wav")
        for passage in passages {
            guard SaySynthesizer().speak(passage.prompt, voice: installed, to: scratch) else {
                throw CleanExit.message("`say` could not read \(passage.id).")
            }
            let wav = try Data(contentsOf: scratch)
            let audio = try AudioFileReader.read(contentsOf: scratch)
            let recorded = RecordedPassage(
                passage: passage, recordedAt: Date(),
                durationSeconds: Double(audio.samples.count) / Double(audio.sampleRate),
                sampleRate: audio.sampleRate, cohort: cohort,
                recordingIdentity: RecordingIdentity.digest(of: wav))
            try store.save(recorded, audio: wav)
        }
        print("Synthesised \(passages.count) passages in \(installed) into \(corpusPath).")
    }
}
