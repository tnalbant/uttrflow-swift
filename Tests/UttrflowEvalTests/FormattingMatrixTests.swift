import Foundation
import Testing
import UttrflowTestSupport

@testable import UttrflowEval

/// The formatting coverage matrix: every class has its floor of cases, and the page matches the corpus.
@Suite("The formatting coverage matrix")
struct FormattingMatrixTests {
    /// The generated page, three folders above this test file.
    static let page = URL(fileURLWithPath: "\(#filePath)").deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Docs/formatting-matrix.md")

    @Test("gives every formatting class at least the covered floor of cases")
    func everyClassIsCovered() {
        for row in FormattingMatrix().rows {
            #expect(
                row.coverage == .covered,
                "\(row.formattingClass.rawValue) has \(row.caseIDs.count) cases, below \(FormattingMatrix.coveredFloor)"
            )
        }
    }

    @Test("reports a class with no cases as uncovered and one with too few as partial")
    func coverageStates() {
        let one = EvaluationCorpus.formatting.filter { $0.classes == [.ellipses] }.prefix(1)
        let rows = FormattingMatrix(cases: Array(one)).rows
        #expect(rows.first { $0.formattingClass == .ellipses }?.coverage == .partial)
        #expect(rows.first { $0.formattingClass == .lists }?.coverage == .uncovered)
    }

    @Test("names every case id once in the corpus")
    func idsAreUnique() {
        let ids = EvaluationCorpus.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("matches Docs/formatting-matrix.md, which is generated from the corpus")
    func pageMatchesCorpus() throws {
        let generated = FormattingMatrix().markdown
        let environment = ProcessInfo.processInfo.environment
        if environment[GoldenFile.updateVariable] == "1", environment["CI"] == nil {
            try generated.write(to: Self.page, atomically: true, encoding: .utf8)
        }
        let recorded = try String(contentsOf: Self.page, encoding: .utf8)
        #expect(recorded == generated, "rerun with \(GoldenFile.updateVariable)=1 to regenerate the page")
    }
}
