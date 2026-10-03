// Tests the probe-log row: its columns, the host classes it derives and the build it names.
import Foundation
import Testing

@testable import UttrflowEval

@Suite("Probe-log row")
struct ProbeLogRowTests {
    private static let gibibyte: Int64 = 1_073_741_824

    private func machine(_ chip: String, gigabytes: Int64) -> MachineDescription {
        MachineDescription(
            chip: chip, memoryBytes: gigabytes * Self.gibibyte,
            operatingSystem: "macOS Version 26.5.1 (Build 25F80)")
    }

    private func row(
        issue: Int? = 3751, machine: MachineDescription, load: HostLoad = HostLoad(oneMinute: 1.25, cores: 18),
        result: String = "range scan 4.7 µs"
    ) -> ProbeLogRow {
        ProbeLogRow(
            issue: issue, date: Date(timeIntervalSince1970: 1_790_000_000), machine: machine, load: load,
            build: "release abc1234", command: "uttrflow-dev probe retrieval", result: result)
    }

    @Test("has a cell for every header column, in order")
    func cellsMatchHeader() throws {
        let header = try #require(ProbeLogRow.header.split(separator: "\n").first)
        let markdown = row(machine: machine("Apple M5 Pro", gigabytes: 48)).markdown(in: .gmt)
        #expect(header.split(separator: "|").count == markdown.split(separator: "|").count)
        #expect(
            markdown
                == "| #3751 | 2026-09-21 | quiet; load 1.2 on 18 cores | Apple M5 Pro | 48 GB "
                + "| macOS Version 26.5.1 (Build 25F80) | release abc1234 | `uttrflow-dev probe retrieval` "
                + "| range scan 4.7 µs |")
    }

    @Test("an 8 GB base chip is minimum-spec and base chip")
    func minimumSpecBaseChip() {
        #expect(row(machine: machine("Apple M1", gigabytes: 8)).hostClasses == [.minimumSpec, .baseChip, .quiet])
    }

    @Test("a tiered chip with 16 GB is neither", arguments: ["Apple M3 Pro", "Apple M2 Max", "Apple M1 Ultra"])
    func tieredChip(chip: String) {
        #expect(row(machine: machine(chip, gigabytes: 16)).hostClasses == [.quiet])
    }

    @Test("a chip that is not Apple silicon is not a base chip")
    func otherChip() {
        #expect(row(machine: machine("Intel(R) Core(TM) i7", gigabytes: 16)).hostClasses == [.quiet])
    }

    @Test("a run queue as long as the cores is not quiet, and an unread load is never quiet")
    func loadDecidesQuiet() {
        let busy = row(machine: machine("Apple M5 Pro", gigabytes: 48), load: HostLoad(oneMinute: 18, cores: 18))
        #expect(busy.hostClasses.isEmpty)
        #expect(busy.markdown(in: .gmt).contains("| load 18.0 on 18 cores |"))
        let unread = row(machine: machine("Apple M5 Pro", gigabytes: 48), load: HostLoad(oneMinute: nil, cores: 18))
        #expect(unread.hostClasses.isEmpty)
        #expect(unread.markdown(in: .gmt).contains("| load unread |"))
    }

    @Test("no issue prints a dash, and a pipe or line break in a cell does not break the table")
    func escapesCells() {
        let markdown = row(issue: nil, machine: machine("Apple M5", gigabytes: 24), result: "a | b\nc")
            .markdown(in: .gmt)
        #expect(markdown.hasPrefix("| — |"))
        #expect(markdown.hasSuffix("| a \\| b c |"))
    }

    @Test("the command names the binary, not where it was built")
    func commandDropsPath() {
        #expect(
            ProbeLogRow.command(from: ["/repo/.build/release/uttrflow-dev", "probe", "retrieval"])
                == "uttrflow-dev probe retrieval")
        #expect(ProbeLogRow.command(from: []) == "")
    }

    @Test("this Mac's load is read")
    func readsLoad() {
        let load = HostLoad.current()
        #expect(load.oneMinute != nil)
        #expect(load.cores > 0)
    }

    @Test("the build names a commit inside a checkout and says so outside one")
    func buildIdentity() throws {
        let inside = BuildIdentity.current(in: URL(fileURLWithPath: #filePath).deletingLastPathComponent().path)
        #expect(inside.hasPrefix(BuildIdentity.configuration + " "))
        #expect(!inside.contains("unknown"))
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        #expect(BuildIdentity.current(in: outside.path) == BuildIdentity.configuration + ", commit unknown")
    }
}
