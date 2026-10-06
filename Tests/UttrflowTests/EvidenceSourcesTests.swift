// Tests the rows the app writes to the evidence ledger from dictation, undo and History.

import Foundation
import Testing
import UttrflowCore
import UttrflowDictionary
import UttrflowHistory

@testable import Uttrflow

@Suite("Evidence sources")
struct EvidenceSourcesTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var today: Int { EvidenceRow.day(of: now) }

    @Test("a used entry writes a use row and an undone correction a revert row, carrying no text")
    func liveRows() {
        let id = UUID()
        #expect(
            EvidenceSources.uses(of: [id], day: today) == [
                EvidenceRow(kind: .use, subject: id.uuidString, day: today, provenance: .dictation)
            ])
        #expect(
            EvidenceSources.revert(of: id, day: today)
                == EvidenceRow(kind: .revert, subject: id.uuidString, day: today, provenance: .undo))
    }

    @Test(
        "History backfills dictionary uses and style counts once, and never a day the ledger already covers")
    func backfill() {
        let entry = DictionaryEntry(word: "Kubernetes", origin: .added, firstSeen: now)
        let old = DictationRecord(
            text: "Deploy it on Kubernetes.", when: now.addingTimeInterval(-3 * 86_400),
            applicationName: "Notes", applicationIdentifier: "com.example.notes")
        let recent = DictationRecord(text: "Kubernetes again", when: now)
        let rows = EvidenceSources.backfill([recent, old], entries: [entry], ledger: [], overrides: .none)
        #expect(rows.allSatisfy { $0.provenance == .migration })
        #expect(rows.filter { $0.kind == .use }.map(\.subject) == [entry.id.uuidString, entry.id.uuidString])
        #expect(rows.filter { $0.kind == .styleMessage }.count == 2)
        #expect(!rows.contains { $0.subject.contains("Deploy") })

        let live = [EvidenceRow(kind: .styleMessage, subject: "plain", day: today, provenance: .dictation)]
        let older = EvidenceSources.backfill([recent, old], entries: [entry], ledger: live, overrides: .none)
        #expect(Set(older.map(\.day)) == [today - 3])
        #expect(EvidenceSources.backfill([old], entries: [entry], ledger: rows, overrides: .none).isEmpty)
    }
}
