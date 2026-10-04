// Tests that the shared seeded generator keeps the sequence every property test was written against, and replays one seed on request.
import Testing
import UttrflowTestSupport

@Suite
struct SeededTests {
    @Test
    func firstValuesMatchTheSequenceTheCopiesProduced() {
        var random = Seeded(seed: 406)

        #expect(
            [random.next(), random.next(), random.next()] == [
                10_447_594_937_129_188_125, 533_806_607_588_122_155, 7_133_130_019_274_433_367,
            ])
    }

    @Test
    func describesItselfInTheFormTheReplayVariableTakes() {
        #expect(Seeded(seed: 42).description == "seed=42")
    }

    @Test
    func runsTheFixedSeedsUnlessOneIsNamedForReplay() {
        #expect(Seeded.seeds(0..<3, environment: [:]) == [0, 1, 2])
        #expect(Seeded.seeds(0..<3, environment: [Seeded.seedVariable: "17"]) == [17])
        #expect(Seeded.seeds(0..<3, environment: [Seeded.seedVariable: "not a number"]) == [0, 1, 2])
    }
}
