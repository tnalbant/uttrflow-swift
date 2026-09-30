import ArgumentParser
import Foundation
import Testing
@testable import uttrflow_bakeoff
@testable import UttrflowEval

struct ReloadLeaksTests {
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
