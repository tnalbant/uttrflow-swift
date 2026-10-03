// Tests what the stop path keeps of a clip released before its speech ends.
import Testing
import UttrflowEval

@Suite("TailCut")
struct TailCutTests {
    @Test func speechEndIsTheLastLoudFrame() {
        let samples = [Float](repeating: 0.5, count: 1600) + [Float](repeating: 0, count: 800)
        #expect(TailCut.speechEnd(of: samples) == 1600)
    }

    @Test func silenceHasNoSpeechEnd() {
        #expect(TailCut.speechEnd(of: [Float](repeating: 0, count: 320)) == 0)
        #expect(TailCut.speechEnd(of: []) == 0)
    }

    @Test func aQuietTailBelowTheFloorIsNotSpeech() {
        let samples = [Float](repeating: 0.5, count: 160) + [Float](repeating: 0.0001, count: 320)
        #expect(TailCut.speechEnd(of: samples) == 160)
    }

    @Test func tapPeriodIsConvertedToCanonicalSamples() {
        #expect(TailCut.tapSamples(tapFrames: 4096, inputRate: 48_000) == 1365)
        #expect(TailCut.tapSamples(tapFrames: 1024, inputRate: 48_000) == 341)
        #expect(TailCut.tapSamples(tapFrames: 0, inputRate: 48_000) == 0)
        #expect(TailCut.tapSamples(tapFrames: 1024, inputRate: 0) == 0)
    }

    @Test func aDrainedStopKeepsTheBlockThatWasFilling() {
        let samples = (0..<1000).map(Float.init)
        #expect(TailCut.kept(samples, cut: 250, tapSamples: 100, phase: 0).count == 300)
        #expect(TailCut.kept(samples, cut: 300, tapSamples: 100, phase: 0).count == 300)
        #expect(TailCut.kept(samples, cut: 250, tapSamples: 100, phase: 60).count == 260)
        #expect(TailCut.kept(samples, cut: 990, tapSamples: 100, phase: 0).count == 1000)
    }

    @Test func anUndrainedStopKeepsOnlyUpToTheCut() {
        let samples = [Float](repeating: 1, count: 100)
        #expect(TailCut.kept(samples, cut: 40, tapSamples: 0, phase: 0).count == 40)
        #expect(TailCut.kept(samples, cut: -5, tapSamples: 0, phase: 0).isEmpty)
    }

    @Test func theLastWordIsJudgedByAlignment() {
        let reference = ["send", "the", "draft"]
        #expect(TailCut.keptLastWord(reference: reference, hypothesis: ["send", "the", "draft", "uh"]))
        #expect(!TailCut.keptLastWord(reference: reference, hypothesis: ["send", "the"]))
        #expect(!TailCut.keptLastWord(reference: reference, hypothesis: ["send", "the", "dra"]))
        #expect(TailCut.keptLastWord(reference: [], hypothesis: ["anything"]))
    }
}
