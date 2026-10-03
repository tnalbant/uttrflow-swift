// The probe-log row every `uttrflow-dev probe` prints after its result. See Docs/probe-log.md.
import ArgumentParser
private import Foundation
internal import UttrflowEval

/// The issue a probe's row cites, and the printing of that row.
struct ProbeLogOptions: ParsableArguments {
    @Option(name: .long, help: "The issue this measurement answers, cited in the probe-log row.")
    var issue: Int?

    func validate() throws {
        if let issue, issue < 1 {
            throw ValidationError("--issue must be 1 or greater.")
        }
    }

    /// Prints the row for `result`, with the load read before the probe ran so its own work is not counted.
    func printRow(result: String, loadBefore: HostLoad) {
        let row = ProbeLogRow(
            issue: issue, date: .now, machine: .current(), load: loadBefore,
            build: BuildIdentity.current(), command: ProbeLogRow.command(from: CommandLine.arguments),
            result: result)
        print("\nProbe-log row, for Docs/probe-log.md:\n\(ProbeLogRow.header)\n\(row.markdown())")
    }
}
