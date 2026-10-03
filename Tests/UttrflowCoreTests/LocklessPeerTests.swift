import Foundation
import Testing

@testable import UttrflowCore

@Suite("Lockless running peers")
struct LocklessPeerTests {
    private func standIn(runningFor seconds: String) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = [seconds]
        try process.run()
        return process
    }

    @Test("An older stand-in that never takes a lock and keeps running is a lasting conflict")
    func lastingLocklessPeerConflicts() throws {
        let older = try standIn(runningFor: "30")
        defer { older.terminate() }
        #expect(LocklessPeer.outlasts(within: .milliseconds(300)) { older.isRunning })
    }

    @Test("A racing launch that exits inside the window is not a conflict")
    func exitingPeerDoesNotConflict() throws {
        let loser = try standIn(runningFor: "0.1")
        #expect(!LocklessPeer.outlasts(within: .seconds(5)) { loser.isRunning })
    }
}
