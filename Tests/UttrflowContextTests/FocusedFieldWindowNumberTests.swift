import Testing

@testable import UttrflowContext

@Suite("Focused field window number reads")
struct FocusedFieldWindowNumberTests {
    @Test("A canceled snapshot does not ask Accessibility for its window number.")
    func canceledSnapshotSkipsTheRead() {
        var reads = 0

        let number = FocusedFieldReader.windowNumber(while: { false }) {
            reads += 1
            return 7
        }

        #expect(number == nil)
        #expect(reads == 0)
    }

    @Test("A snapshot discards the window number if it is superseded during the read.")
    func supersededSnapshotDiscardsTheRead() {
        var checks = 0
        var reads = 0

        let number = FocusedFieldReader.windowNumber(while: {
            checks += 1
            return checks == 1
        }) {
            reads += 1
            return 7
        }

        #expect(number == nil)
        #expect(reads == 1)
    }
}
