// Simulates the formatting decisions made from a focused Accessibility field.
import ArgumentParser
import UttrflowCore

struct SimulateField: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "simulate-field", abstract: "Show formatting policies for a simulated AX field."
    )

    @Option(help: "Accessibility role, for example AXSearchField or AXTextField.")
    var role: String

    @Flag(help: "The field accepts multiple lines.")
    var multiline = false

    func run() throws {
        let app = AppContext(accessibilityRole: role, isMultiline: multiline)
        let situation = SituationResolver.resolve(from: app)
        let formatter = DestinationFormatter.standard(for: situation)
        print("role: \(role)")
        print("multiline: \(multiline)")
        print("first word: \(String(describing: formatter.firstWord))")
        print("terminal stop: \(String(describing: formatter.terminalStop))")
        print("single line: \(formatter.layout.contains(.singleLine))")
    }
}
