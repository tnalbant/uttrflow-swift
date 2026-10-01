// The attributed values Apple attaches to a speech result, reduced to raw transcript values.

import CoreMedia
import Foundation
import Speech
import UttrflowCore

enum AppleSpeechTranscriptMapping {
    /// Keeps word confidence only when every spoken token has both a real confidence and a time range.
    static func segment(_ text: AttributedString, audioRange: CMTimeRange) -> RawSegment? {
        let start = audioRange.start.seconds
        let end = CMTimeRangeGetEnd(audioRange).seconds
        guard start.isFinite, end.isFinite, end >= start else { return nil }

        let ranges = tokenRanges(in: text)
        let words = ranges.compactMap { word(in: text, range: $0) }
        let completeWords = !ranges.isEmpty && words.count == ranges.count ? words : nil
        return RawSegment(
            text: String(text.characters), start: start, end: end, words: completeWords)
    }

    /// Finds whitespace-delimited text ranges without discarding the attributed string's indices.
    private static func tokenRanges(in text: AttributedString) -> [Range<AttributedString.Index>] {
        var ranges: [Range<AttributedString.Index>] = []
        var start: AttributedString.Index?
        for index in text.characters.indices {
            if text.characters[index].isWhitespace {
                if let tokenStart = start {
                    ranges.append(tokenStart..<index)
                    start = nil
                }
            } else if start == nil {
                start = index
            }
        }
        if let start { ranges.append(start..<text.endIndex) }
        return ranges
    }

    /// Reads both SDK attributes from a token only when each covers the entire token.
    private static func word(
        in text: AttributedString, range: Range<AttributedString.Index>
    ) -> RawWord? {
        let runs = Array(text[range].runs)
        guard runs.count == 1,
            let confidence = runs[0][AttributeScopes.SpeechAttributes.ConfidenceAttribute.self],
            confidence.isFinite, (0...1).contains(confidence),
            let time = runs[0][AttributeScopes.SpeechAttributes.TimeRangeAttribute.self]
        else { return nil }
        let start = time.start.seconds
        let end = CMTimeRangeGetEnd(time).seconds
        guard start.isFinite, end.isFinite, end >= start else { return nil }
        return RawWord(text: String(text[range].characters), start: start, end: end, probability: confidence)
    }
}
