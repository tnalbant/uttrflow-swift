import Foundation
import UttrflowClipboard
import UttrflowCore
import UttrflowInput
import UttrflowPipeline
import UttrflowTestSupport
import Testing

@testable import Uttrflow

@MainActor
@Suite("Menu bar clipboard snapshot refresh")
struct MenuBarClipRefreshTests {
    private actor InsertionRecorder: TextInserting {
        private(set) var inserted: [String] = []

        func insert(_ text: String) async throws(TextInsertionError) -> InsertionAttempt {
            inserted.append(text)
            return InsertionAttempt(.accessibility, arrival: .confirmed)
        }
    }

    @Test("a captured clip action still inserts its clip after a newer copy shifts the list")
    func capturedClipActionUsesIdentity() async throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root, account: HeldSession(signedIn: true).layer)
        let store = ClipboardStore(file: ClipboardStore.defaultFile(in: sandbox.root))
        let retention = ClipRetention(days: 30, now: .now)
        let selected = Clip(text: "The clip the user chose", kind: .text, copiedAt: .now)
        _ = try await store.record(selected, keeping: retention)

        await app.readMenuClips()
        let captured = try #require(app.menuBarPresentation.clips.first?.insert.intent)

        _ = try await store.record(
            Clip(text: "A newer copy", kind: .text, copiedAt: .now.addingTimeInterval(1)),
            keeping: retention)
        await app.readMenuClips()
        let insertion = InsertionRecorder()
        app.clipInserter = insertion

        app.carryOut(captured)

        try await eventually { await insertion.inserted == [selected.text] }
    }

    @Test("a captured recent action still inserts its dictation after a newer one arrives")
    func capturedRecentActionUsesIdentity() async throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root, account: HeldSession(signedIn: true).layer)
        app.drawsWindows = false
        app.render(
            .inserted(
                DictationOutcome(
                    text: "The dictation the user chose", method: .accessibility, cleanedBy: .rules)))
        let captured = try #require(app.menuBarPresentation.lastDictation?.insert.intent)

        app.render(
            .inserted(
                DictationOutcome(
                    text: "A newer dictation", method: .accessibility, cleanedBy: .rules)))
        let insertion = InsertionRecorder()
        app.clipInserter = insertion

        app.carryOut(captured)

        try await eventually { await insertion.inserted == ["The dictation the user chose"] }
    }

    @Test("refreshing after a panel edit updates an already-drawn menu presentation")
    func panelEditRefreshesMenuSnapshot() async throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        let store = ClipboardStore(file: ClipboardStore.defaultFile(in: sandbox.root))
        let retention = ClipRetention(days: 30, now: .now)
        let recorded = try await store.record(
            Clip(text: "before edit", kind: .text, copiedAt: .now), keeping: retention)
        let clip = try #require(recorded.first { $0.text == "before edit" })

        await app.readMenuClips()
        #expect(app.menuBarPresentation.clips.first?.title == "before edit")

        try await store.setText("after edit", of: clip.id, keeping: retention)
        #expect(await store.clips(keeping: retention).first?.text == "after edit")
        await app.readMenuClips()

        #expect(app.menuBarPresentation.clips.first?.title == "after edit")
    }
}
