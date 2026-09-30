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
            richText: "<ul class=\"checklist\"><li class=\"checked\">Milk</li><li>Tea</li></ul>")

        #expect(memo.progress(of: note)?.done == 1)
        #expect(memo.progress(of: note)?.total == 2)
        #expect(parses.withLock { $0 } == 1)

        let edited = Clip(
            id: note.id, text: note.text, kind: note.kind, copiedAt: note.copiedAt,
            richText: "<ul class=\"checklist\"><li>Milk</li></ul>")

        #expect(memo.progress(of: edited)?.done == 0)
        #expect(memo.progress(of: edited)?.total == 1)
        #expect(parses.withLock { $0 } == 2)
    }
}
