// The `compare` command: the regression gate for a run a scorer outside this package reduced to counts.
import ArgumentParser
private import Foundation
private import UttrflowEval

/// Gates a run written as an accuracy baseline file, so the bench and the transcription gate judge with one rule.
struct CompareRuns: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "compare",
        abstract: "Compare a measured run, written as a baseline file, with a stored baseline."
    )

    @Option(name: .long, help: "The run to judge, in the accuracy baseline format.")
    var measured: String

    @Option(name: .long, help: "The stored baseline to compare with.")
    var baseline: String

    @Flag(name: .long, help: "Write the measured run to --baseline as the new point of comparison.")
    var saveBaseline = false

    @Flag(name: .long, help: "Exit non-zero when any slice has got worse, or no verdict is possible.")
    var failOnRegression = false

    @Option(name: .long, help: "How many percentage points a rate may move before it counts.")
    var tolerance = 0.5

    @Option(name: .long, help: "Reference words a slice needs before it is judged.")
    var minimumWords = RegressionTolerance.standard.minimumReferenceWords

    func run() throws {
        let run = try AccuracyBaseline.read(from: URL(fileURLWithPath: measured))
        try BaselineGate(
            path: baseline, saveBaseline: saveBaseline, failOnRegression: failOnRegression,
            tolerance: RegressionTolerance(percentagePoints: tolerance, minimumReferenceWords: minimumWords)
        ).judge(run)
    }
}
