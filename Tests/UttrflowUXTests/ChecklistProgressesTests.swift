// Verifies checklist counts are reused while a note's formatted content stays the same.
import Foundation
import Synchronization
import UttrflowClipboard
import Testing

@testable import UttrflowUX

@Suite("Checklist counts in the quick panel")
struct ChecklistProgressesTests {
    @Test("parses a note once and refreshes its count when its HTML changes")
    func memoizesProgressByClipAndContent() {
        let parses = Mutex(0)
        let memo = ChecklistProgresses { html in
            parses.withLock { $0 += 1 }
            return NoteChecklist.progress(in: html)
        }
        let note = Clip(
            id: UUID(), text: "Shopping list", kind: .text, copiedAt: Date(),
            richText: "<ul><li class=\"checked\">Milk</li><li class=\"unchecked\">Tea</li></ul>")

        #expect(memo.progress(of: note)?.done == 1)
        #expect(memo.progress(of: note)?.total == 2)
        #expect(parses.withLock { $0 } == 1)

        let edited = Clip(
            id: note.id, text: note.text, kind: note.kind, copiedAt: note.copiedAt,
            richText: "<ul><li class=\"unchecked\">Milk</li></ul>")

        #expect(memo.progress(of: edited)?.done == 0)
        #expect(memo.progress(of: edited)?.total == 1)
        #expect(parses.withLock { $0 } == 2)
    }

    @Test("refreshing the same clip with changed checklist HTML updates its panel row")
    func refreshesProgressAfterChecklistChanges() {
        let copiedAt = PanelFixture.now
        let note = Clip(
            id: UUID(), text: "Shopping list", kind: .text, copiedAt: copiedAt,
            richText: "<ul><li class=\"checked\">Milk</li><li class=\"unchecked\">Tea</li></ul>")
        var snapshot = PanelFixture.panel([note])

        #expect(PanelPresenter.present(snapshot).rows[0].checklist == "1 of 2")

        let edited = Clip(
            id: note.id, text: note.text, kind: note.kind, copiedAt: copiedAt,
            richText: "<ul><li class=\"unchecked\">Milk</li></ul>")
        snapshot.install(
            [edited], missingImages: [], formattableLanguages: [], now: copiedAt)

        #expect(PanelPresenter.present(snapshot).rows[0].checklist == "0 of 1")
    }

    @Test("prunes formatted HTML for clips evicted from the panel")
    func prunesEvictedClipHTML() {
        let parses = Mutex(0)
        let memo = ChecklistProgresses { html in
            parses.withLock { $0 += 1 }
            return NoteChecklist.progress(in: html)
        }
        let copiedAt = PanelFixture.now
        let retained = Clip(
            id: UUID(), text: "Keep", kind: .text, copiedAt: copiedAt,
            richText: "<ul><li class=\"checked\">Keep</li></ul>")
        let evicted = Clip(
            id: UUID(), text: "Evict", kind: .text, copiedAt: copiedAt,
            richText: "<ul><li class=\"unchecked\">Evict</li></ul>")

        _ = memo.progress(of: retained)
        _ = memo.progress(of: evicted)
        memo.prune(to: [retained.id])

        #expect(memo.progress(of: retained)?.total == 1)
        #expect(memo.progress(of: evicted)?.total == 1)
        #expect(parses.withLock { $0 } == 3)
    }
}
