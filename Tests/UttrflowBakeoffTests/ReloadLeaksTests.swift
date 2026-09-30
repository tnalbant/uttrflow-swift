import ArgumentParser
import Foundation
import Testing
@testable import uttrflow_bakeoff
@testable import UttrflowEval

struct ReloadLeaksTests {
    @Test("scorecard and fixture report use judged shown rows for category precision")
    func scorecardMatchesFixtureReportPrecision() throws {
        let results = [
            FixtureResult(
                name: "chat/right", category: "chat", typed: "hello", hit: true, judged: true,
                conforms: true, elapsedMs: 10, first: "hello", raw: nil, invented: false),
            FixtureResult(
                name: "chat/wrong", category: "chat", typed: "world", hit: false, judged: true,
                conforms: true, elapsedMs: 12, first: "wrong", raw: nil, invented: false),
            FixtureResult(
                name: "chat/unjudged", category: "chat", typed: "continuation", hit: true, judged: false,
                conforms: true, elapsedMs: 14, first: "continuation", raw: nil, invented: false),
        ]
        let report = FixtureReport(results: results)
        let category = try #require(report.summary.categories.first)
        #expect(category.shown == 2)
        #expect(category.right == 1)

        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try report.write(to: directory.appending(path: "fixture.json").path)
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Scripts/predict_scorecard.py")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script.path, directory.appending(path: "fixture.json").path]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(text.contains("precision 50.00 % (1/2 judged shown, 1 wrong"))
        #expect(
            text.contains(
                "chat       n=   3 hit  67 %  register 100 %  p50   12  precision   50.0%  wrong   1")
        )
    }

    @Test("stored bake-off results retain surface metrics and old files still decode")
    func storedSurfaceMetricsRemainBackwardCompatible() throws {
        let legacy = Data(
            #"{"passRate":0,"meanSimilarity":0,"medianSeconds":0,"slowestSeconds":0,"declinedCount":0,"lostWordCount":0,"cases":[{"caseID":"legacy","category":"everyday","similarity":1,"lost":[],"passed":true,"declined":false}]}"#
                .utf8)
        let old = try JSONDecoder().decode(StoredReport.self, from: legacy)
        #expect(old.meanMarkAccuracy == nil)
        #expect(old.meanCaseAccuracy == nil)
        #expect(old.cases.first?.markAccuracy == nil)
        #expect(old.cases.first?.caseAccuracy == nil)

        let score = CaseScore(
            caseID: "surface", similarity: 1, markAccuracy: 0.5, caseAccuracy: 0.75,
            keptEverythingRequired: true, lost: [], isExact: false)
        let report = EvaluationReport(label: "surface", scores: [score], durations: [])
        let measurement = Measurement(description: .rules, report: report)
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        try ResultStore(directory: directory).save(measurement)
        let stored = try #require(ResultStore(directory: directory).all().first?.report)
        #expect(stored.meanMarkAccuracy == 0.5)
        #expect(stored.meanCaseAccuracy == 0.75)
        #expect(stored.cases.first?.markAccuracy == 0.5)
        #expect(stored.cases.first?.caseAccuracy == 0.75)
    }

    @Test("checkpoints must be positive before the median is calculated")
    func checkpointsMustBePositive() throws {
        #expect(try ReloadLeaks.parseCheckpoints("1,5,20") == [1, 5, 20])
        #expect(throws: ValidationError.self) {
            try ReloadLeaks.parseCheckpoints("0")
        }
        #expect(throws: ValidationError.self) {
            try ReloadLeaks.parseCheckpoints("1,0,2")
        }
    }

    @Test("checkpoints must remain ascending whole numbers")
    func checkpointsMustBeAscendingWholeNumbers() {
        #expect(throws: ValidationError.self) {
            try ReloadLeaks.parseCheckpoints("5,1")
        }
        #expect(throws: ValidationError.self) {
            try ReloadLeaks.parseCheckpoints("1,x,5")
        }
        #expect(throws: ValidationError.self) {
            try ReloadLeaks.parseCheckpoints("1,,5")
        }
        #expect(throws: ValidationError.self) {
            try ReloadLeaks.parseCheckpoints(",1,5")
        }
        #expect(throws: ValidationError.self) {
            try ReloadLeaks.parseCheckpoints("1,5,")
        }
    }
}
