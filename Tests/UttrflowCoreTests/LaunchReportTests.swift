// Tests that a launch's time to the shortcut is said, read back and timed from the kernel's start.

import Darwin
import Testing

@testable import UttrflowCore

@Suite("The launch's time to the dictation shortcut")
struct LaunchReportTests {
    @Test("is read back from the line it is logged as, for both outcomes and a missing start")
    func roundTrips() {
        for outcome in LaunchReport.Outcome.allCases {
            for age in [Duration.milliseconds(412), nil] {
                let report = LaunchReport(age: age, outcome: outcome)
                #expect(LaunchReport(in: report.logged) == report)
            }
        }
    }

    @Test("says unknown rather than a number when the start time is missing")
    func missingStartIsSaid() {
        let report = LaunchReport(age: nil, outcome: .armed)
        #expect(report.milliseconds == nil)
        #expect(report.logged == "shortcut armed unknown ms after process start")
    }

    @Test("is found behind whatever the log tool prints in front of it")
    func foundInsideALogLine() {
        let line =
            "2026-10-03 10:00:00.000 Df Uttrflow[123:456] [com.uttrflow.Uttrflow:launch] "
            + "shortcut armed 512 ms after process start"
        #expect(LaunchReport(in: line) == LaunchReport(age: .milliseconds(512), outcome: .armed))
    }

    @Test("is not found in other lines that mention the shortcut")
    func otherLinesAreNotReports() {
        let lines = [
            "the dictation shortcut is not armed: shortcutUnavailable",
            "shortcut armed 12 ms after process",
            "shortcut opened 12 ms after process start",
            "shortcut armed soon ms after process start",
            "shortcut armed -4 ms after process start",
            "shortcut armed 12 ms after process start and more",
        ]
        for line in lines { #expect(LaunchReport(in: line) == nil, "\(line)") }
    }

    @Test("this process's age is a positive time, and a backwards clock gives none")
    func processAge() throws {
        let age = try #require(ProcessAge.current())
        #expect(age > .zero)
        let later = timeval(tv_sec: 100, tv_usec: 250_000)
        let earlier = timeval(tv_sec: 99, tv_usec: 750_000)
        #expect(ProcessAge.between(earlier, and: later) == .milliseconds(500))
        #expect(ProcessAge.between(later, and: earlier) == nil)
    }

    @Test("the milestone keeps its first outcome and refuses a second")
    @MainActor
    func milestoneOnce() {
        let milestone = LaunchMilestone { nil }
        #expect(milestone.shortcutSettled(.armed) == LaunchReport(age: nil, outcome: .armed))
        #expect(milestone.shortcutSettled(.refused) == nil)
        #expect(milestone.report == LaunchReport(age: nil, outcome: .armed))
    }
}
