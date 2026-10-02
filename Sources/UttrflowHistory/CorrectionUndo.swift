// Puts one recorded correction back into a dictation's text and names the dictionary entry to charge.
public import struct Foundation.UUID
import UttrflowCore

/// Undoes one correction on a copy of the record, so no field is forgotten on the way.
extension DictationRecord {
    /// A copy with the change put back and its entry to charge, or `nil`. See Docs/core-history-undo.md.
    public func undoing(_ correction: UUID) -> (record: DictationRecord, entryID: UUID)? {
        guard let changes,
            let target = changes.corrections.firstIndex(where: { $0.id == correction }),
            !changes.corrections[target].isUndone
        else { return nil }

        let reverted = changes.corrections[target]
        var undone = self
        // Read before the flag flips, so this change's words are still located where they were written.
        undone.text = restoring(reverted, among: changes.corrections)
        undone.changes?.corrections[target].isUndone = true
        return (undone, reverted.entryID)
    }

    /// ``text`` with the reverted words put back, or unchanged when they are not where the ranges say.
    private func restoring(
        _ reverted: RecordedCorrection, among corrections: [RecordedCorrection]
    ) -> String {
        let words = text.spokenWordRanges()
        let (start, length) =
            corrections.allSatisfy { $0.writtenWordIndex != nil }
            ? located(reverted, among: corrections)
            : counted(reverted, among: corrections)

        guard length > 0, start >= 0, start + length <= words.count else { return text }
        let span = words[start].lowerBound..<words[start + length - 1].upperBound
        let written = reverted.wrote.spokenWords()
        let present = text[span].spokenWords()
        guard present.count == written.count,
            zip(present, written).allSatisfy({ sameWord($0.0, $0.1) })
        else { return text }

        var repaired = String(text[text.startIndex..<span.lowerBound])
        repaired += restoringPunctuation(in: text[span], with: reverted.heard)
        repaired += text[span.upperBound...]
        return repaired
    }

    /// Replaces matching cores, keeping stored punctuation and same-count spacing.
    private func restoringPunctuation(in written: Substring, with heard: String) -> String {
        let ranges = written.spokenWordRanges()
        let heardRanges = heard.spokenWordRanges()
        guard let firstWritten = ranges.first, let lastWritten = ranges.last,
            !heardRanges.isEmpty
        else { return heard }

        if ranges.count == heardRanges.count {
            var restored = ""
            var writtenCursor = written.startIndex
            for (range, heardRange) in zip(ranges, heardRanges) {
                restored += written[writtenCursor..<range.lowerBound]
                let shape = WordShape(String(written[range]))
                restored += shape.prefix + WordShape(String(heard[heardRange])).core + shape.suffix
                writtenCursor = range.upperBound
            }
            restored += written[writtenCursor...]
            return restored
        }

        var restored = ""
        var heardCursor = heard.startIndex
        for (index, range) in heardRanges.enumerated() {
            restored += heard[heardCursor..<range.lowerBound]
            let shape = WordShape(String(heard[range]))
            let prefix = index == 0 ? WordShape(String(written[firstWritten])).prefix : shape.prefix
            let suffix =
                index == heardRanges.count - 1
                ? WordShape(String(written[lastWritten])).suffix : shape.suffix
            restored += prefix + shape.core + suffix
            heardCursor = range.upperBound
        }
        restored += heard[heardCursor...]
        return restored
    }

    /// Allows only the first letter's case to differ when comparing corrected word cores.
    private func sameWord(_ present: Substring, _ written: Substring) -> Bool {
        let actualCore = WordShape(String(present)).core
        let writtenCore = WordShape(String(written)).core
        guard let actualFirst = actualCore.first, let writtenFirst = writtenCore.first else { return false }
        return actualFirst.lowercased() + String(actualCore.dropFirst())
            == writtenFirst.lowercased() + String(writtenCore.dropFirst())
    }

    /// The words from where the pipeline found them in the stored text, moved by earlier undos only.
    private func located(
        _ reverted: RecordedCorrection, among corrections: [RecordedCorrection]
    ) -> (start: Int, length: Int) {
        guard let index = reverted.writtenWordIndex else { return (0, 0) }
        var shift = 0
        for correction in corrections where correction.isUndone {
            guard let other = correction.writtenWordIndex, other < index else { continue }
            shift += correction.heard.spokenWords().count - correction.wrote.spokenWords().count
        }
        return (index + shift, reverted.wrote.spokenWords().count)
    }

    /// The words from the heard-space range, for a record that does not say where they landed.
    private func counted(
        _ reverted: RecordedCorrection, among corrections: [RecordedCorrection]
    ) -> (start: Int, length: Int) {
        var shift = 0
        for correction in corrections.sorted(by: { $0.wordRange.lowerBound < $1.wordRange.lowerBound }) {
            let standing = correction.isUndone ? correction.heard : correction.wrote
            let count = standing.spokenWords().count
            if correction.id == reverted.id {
                return (correction.wordRange.lowerBound + shift, count)
            }
            shift += count - correction.wordRange.count
        }
        return (0, 0)
    }
}

/// Splits words the way the pipeline counts an utterance, so a correction's range indexes the same words.
extension StringProtocol {
    /// The whitespace-separated words of this text; splitting on letters would put "don't" at two indices.
    fileprivate func spokenWords() -> [SubSequence] {
        split(whereSeparator: \.isWhitespace)
    }
}

/// Word positions for splicing.
extension StringProtocol {
    /// Where each spoken word of this text begins and ends.
    fileprivate func spokenWordRanges() -> [Range<Index>] {
        spokenWords().map { $0.startIndex..<$0.endIndex }
    }
}
