import ArgumentParser
import Foundation
import UttrflowCore

/// Launches a built bundle and prints how long after process start its dictation shortcut was armed.
struct Launch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Time a built Uttrflow.app from process start to its dictation shortcut, once per run.",
        discussion: """
            Each run starts the bundle against a fresh temporary container (signed in, onboarded, \
            no login item) and reads the line the app logs under \
            \(LaunchMilestone.subsystem):\(LaunchMilestone.category). See Docs/startup.md.
            """
    )

    @Option(name: .long, help: "The built bundle to launch.")
    var app = "dist/Uttrflow.app"

    @Option(name: .long, help: "How many launches to time.")
    var runs = 5

    @Option(name: .long, help: "Seconds to wait for one launch's report.")
    var timeout = 60

    func run() async throws {
        let executable = try executable(in: URL(fileURLWithPath: app))
        var reports: [LaunchReport] = []
        for index in 1...max(runs, 1) {
            let report = try await timeOneLaunch(of: executable)
            print("  run \(index): \(report?.logged ?? "no report within \(timeout) s; is dictation on?")")
            if let report { reports.append(report) }
        }
        let times = reports.compactMap(\.milliseconds).sorted()
        guard let first = times.first, let last = times.last else { return }
        print("  \(times.count) timed: min \(first) ms, median \(times[times.count / 2]) ms, max \(last) ms")
    }

    private func executable(in bundle: URL) throws -> URL {
        guard let name = Bundle(url: bundle)?.executableURL else {
            throw ValidationError("\(bundle.path) is not an app bundle; build one with `make app`")
        }
        return name
    }

    private func timeOneLaunch(of executable: URL) async throws -> LaunchReport? {
        let container = FileManager.default.temporaryDirectory
            .appending(path: "uttrflow-launch-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }
        let stream = LaunchLogStream()
        try stream.start()
        defer { stream.stop() }
        // `log stream` attaches asynchronously, and a line logged before it does is never shown.
        try await Task.sleep(for: .seconds(1))
        let launched = Process()
        launched.executableURL = executable
        launched.environment = ProcessInfo.processInfo.environment.merging(
            ["UTTRFLOW_TEST_CONTAINER": container.path]) { _, new in new }
        try launched.run()
        defer { launched.terminate(); launched.waitUntilExit() }
        return await stream.firstReport(within: .seconds(timeout))
    }
}

/// `log stream` over the launch category until a report appears; unchecked because `lock` guards the state.
private final class LaunchLogStream: @unchecked Sendable {
    private let process = Process()
    private let output = Pipe()
    private let lock = NSLock()
    private var buffer = ""
    private var report: LaunchReport?

    func start() throws {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        let predicate =
            "subsystem == \"\(LaunchMilestone.subsystem)\" AND category == \"\(LaunchMilestone.category)\""
        process.arguments = ["stream", "--style", "compact", "--predicate", predicate]
        process.standardOutput = output
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.read(handle.availableData)
        }
        try process.run()
    }

    func stop() {
        output.fileHandleForReading.readabilityHandler = nil
        process.terminate()
        process.waitUntilExit()
    }

    func firstReport(within limit: Duration) async -> LaunchReport? {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline {
            if let found = lock.withLock({ report }) { return found }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return lock.withLock { report }
    }

    private func read(_ data: Data) {
        lock.withLock {
            buffer += String(decoding: data, as: UTF8.self)
            let lines = buffer.split(separator: "\n", omittingEmptySubsequences: false)
            buffer = String(lines.last ?? "")
            for line in lines.dropLast() where report == nil {
                report = LaunchReport(in: String(line))
            }
        }
    }
}
