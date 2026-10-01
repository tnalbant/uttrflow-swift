import Foundation
import UttrflowClipboard
import UttrflowCore
import Testing

@testable import Uttrflow

@MainActor
@Suite("Menu bar clipboard snapshot refresh")
struct MenuBarClipRefreshTests {
    @Test("refreshing after a panel edit updates an already-drawn menu presentation")
    func panelEditRefreshesMenuSnapshot() async throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        let store = ClipboardStore(file: ClipboardStore.defaultFile(in: sandbox.root))
        let retention = ClipRetention(days: 30, now: .now)
        let clip = try await store.record(
            Clip(text: "before edit", kind: .text, copiedAt: .now), keeping: retention)

        await app.readMenuClips()
        #expect(app.menuBarPresentation.clips.first?.text == "before edit")

        try await store.setText("after edit", of: clip.id, keeping: retention)
        #expect(await store.clips(keeping: retention).first?.text == "after edit")
        await app.readMenuClips()

        #expect(app.menuBarPresentation.clips.first?.text == "after edit")
    }
}
