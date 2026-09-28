// The `context` command: shows what Uttrflow can see of the frontmost app.
import AppKit
import ArgumentParser
import Foundation
import UttrflowContext
import UttrflowCore
import UttrflowPermissions

/// Shows what Uttrflow can see of the app you are working in, which is invisible in the text.
struct Context: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Report what Uttrflow can see of the frontmost app."
    )

    @Option(name: .shortAndLong, help: "Seconds to wait so you can bring another app forward.")
    var delay: Int = 3

    @Option(
        name: .long, help: "Read this running application by bundle identifier instead of the frontmost one.")
    var bundle: String?

    @Flag(name: .long, help: "Print what tab-to-complete would show the model from around the focused field.")
    var surroundings = false

    func run() async throws {
        if let bundle {
            try await printSurroundings(ofBundle: bundle)
            return
        }
        if delay > 0 {
            print("Bring the app you want to inspect to the front. Reading in \(delay)s…")
            try await Task.sleep(for: .seconds(delay))
        }

        let clock = ContinuousClock()
        let start = clock.now
        let context = await MacContextEngine().currentContext()
        let elapsed = start.duration(to: clock.now)

        print("")
        print("  application   \(context.applicationName ?? "—")")
        print("  bundle id     \(context.bundleIdentifier ?? "—")")
        print("  window        \(context.documentName ?? "—")")
        print("  selected      \(context.selectedText.map(preview) ?? "—")")
        print("  read in       \(format(elapsed))s")

        let accessibility = await AccessibilityPermissionGate().status()
        if accessibility != .granted {
            print("\nWithout Accessibility access the window title and selection stay empty.")
            print("The application name does not need it.")
        }
    }

    /// Dumps the window title and the text around the focused field of one running application, exactly as the prompt would carry them.
    private func printSurroundings(ofBundle bundle: String) async throws {
        let running = await MainActor.run {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first
        }
        guard let running else {
            print("no running application with bundle identifier \(bundle)")
            throw ExitCode.failure
        }
        let app = FrontmostApp(
            processIdentifier: running.processIdentifier, bundleIdentifier: bundle,
            name: running.localizedName ?? bundle)
        var snaps: [Double] = [], arounds: [Double] = []
        for _ in 0..<30 {
            let a = DispatchTime.now().uptimeNanoseconds; _ = FocusedFieldReader.snapshot(app: app)
            let b = DispatchTime.now().uptimeNanoseconds; _ = FocusedFieldReader.surroundings(of: app)
            let c = DispatchTime.now().uptimeNanoseconds
            snaps.append(Double(b - a) / 1e6); arounds.append(Double(c - b) / 1e6)
        }
        snaps.sort(); arounds.sort()
        print("PROBE timing ms snapshot p50=\(snaps[15]) max=\(snaps[29])  surroundings p50=\(arounds[15]) max=\(arounds[29])")
        if let s = FocusedFieldReader.snapshot(app: app) {
            print("PROBE role=\(s.role) subrole=\(s.subrole ?? "-") desc=\(s.accessibilityDescription ?? "-") secure=\(s.isSecure)")
            print("PROBE value=\(s.value.map { "\($0.count) chars" } ?? "nil") selection=\(s.selection.map { "\($0)" } ?? "nil") caret=\(s.caret.map { "\($0)" } ?? "nil") field=\(s.field.map { "\($0)" } ?? "nil")")
            print("PROBE line=\(s.currentLine) atEnd=\(s.caretAtLineEnd) placement=\(s.placement.map { "\($0)" } ?? "nil") prose=\(s.isProse)")
        } else { print("PROBE no snapshot") }
        guard let around = FocusedFieldReader.surroundings(of: app) else {
            print("nothing around a focused field in \(app.name): no field focused, or no window")
            throw ExitCode.failure
        }
        print("  window title  \(around.windowTitle ?? "—")")
        print("  around        \(around.text?.count ?? 0) characters\n")
        print(around.text ?? "")
    }

    private func preview(_ text: String) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.count > 60 ? collapsed.prefix(60) + "…" : collapsed
    }

    private func format(_ duration: Duration) -> String {
        String(
            format: "%.3f",
            duration.inSeconds)
    }
}
