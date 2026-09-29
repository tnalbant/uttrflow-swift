// Turns a recogniser's raw output into the product's Transcription.
public import UttrflowCore

extension RawTranscript {
    /// Turns any recogniser's raw output into the product's ``Transcription``, shifted by `offset`.
    public func transcription(
        audioDuration: Duration, startingAt offset: Duration = .zero
    ) -> Transcription {
        Transcription(
            text: Self.cleaned(text),
            detectedLanguage: detectedLanguage,
            segments: segments.map { $0.transcriptionSegment(shiftedBy: offset) },
            audioDuration: audioDuration,
            effort: effort
        )
    }

    /// Seconds between the recogniser's last segment and the audio end that suggests a decode stopped at the cap.
    public static let cappedDecodeGap: Duration = .milliseconds(2_500)

    /// Whether the last segment ends well before the audio did, which is what a capped decode looks like from outside.
    public func appearsCapped(audioDuration: Duration) -> Bool {
        guard let lastEnd = segments.last?.end else { return false }
        return audioDuration.inSeconds - lastEnd > Self.cappedDecodeGap.inSeconds
    }

    private var detectedLanguage: DetectedLanguage? {
        guard let languageIdentifier, let code = LanguageCode(languageIdentifier) else { return nil }
        return DetectedLanguage(code: code, confidence: languageProbability)
    }

    /// Words recognisers use for non-speech markers; unknown bracketed or starred words stay as dictated. See `Docs/silence.md`.
    static let markerWords: Set<String> = [
        "pain", "painful", "thud", "thunk", "puff", "crack", "gunshot",
        "blank", "audio", "silence", "silent", "quiet", "pause", "no", "speech", "sound", "sounds",
        "noise", "noises", "static", "background", "inaudible", "unintelligible", "indistinct",
        "muffled", "crosstalk", "chatter", "music", "musical", "song", "singing", "humming",
        "laughter", "laughs", "laughing", "chuckles", "applause", "clapping", "cheering",
        "coughs", "coughing", "sighs", "sighing", "sniffs", "breathing", "breath", "beep",
        "beeping", "chime", "ringing", "buzzing", "clicking", "typing", "footsteps", "wind",
        "rain", "thunder", "foreign", "language", "speaking", "upbeat", "soft", "gentle",
        "dramatic", "tense", "loud", "faint", "distant", "continues", "continued", "playing",
        "plays", "ends",
    ]

    /// Whether every word inside a marker is a known non-speech description.
    static func isMarker(_ inside: Substring) -> Bool {
        let words = inside.split(whereSeparator: { $0.isWhitespace || $0 == "_" || $0 == "-" })
        guard !words.isEmpty, words.count <= 3 else { return false }
        return words.allSatisfy { markerWords.contains($0.lowercased()) }
    }

    /// The same removal over the recogniser's words, so the text and the word list cannot fall out of step.
    static func cleaned(_ words: [TranscribedWord]) -> [TranscribedWord] {
        var kept: [TranscribedWord] = []
        var index = words.startIndex

        while index < words.endIndex {
            if words[index].text.allSatisfy({ $0 == "*" }), words[index].text.count >= 3 {
                index += 1
                continue
            }
            let opener = words[index].text.first
            guard opener == "[" || opener == "(" || opener == "*" else {
                kept.append(words[index])
                index += 1
                continue
            }
            let closer: Character = opener == "[" ? "]" : opener == "(" ? ")" : "*"
            guard let close = words[index...].firstIndex(where: { $0.text.hasSuffix(String(closer)) })
            else {
                kept.append(words[index])
                index += 1
                continue
            }
            let inside = words[index...close].map(\.text).joined(separator: " ").dropFirst().dropLast()
            if !isMarker(inside) {
                kept.append(contentsOf: words[index...close])
            }
            index = words.index(after: close)
        }
        return kept
    }

    /// Removes standalone non-speech markers. See `Docs/silence.md`.
    static func cleaned(_ text: String) -> String {
        var result: [Substring] = []
        var remainder = Substring(text)

        while let open = remainder.firstIndex(where: { $0 == "[" || $0 == "(" || $0 == "*" }) {
            if remainder[open] == "*" {
                let runEnd = remainder[open...].prefix(while: { $0 == "*" }).endIndex
                let runLength = remainder.distance(from: open, to: runEnd)
                if runLength >= 3 {
                    let before = remainder[..<open].last
                    let after = runEnd < remainder.endIndex ? remainder[runEnd] : nil
                    let standsAlone =
                        (before == nil || before?.isWhitespace == true)
                        && (after == nil || after?.isWhitespace == true || after?.isPunctuation == true)
                    result.append(remainder[..<open])
                    if !standsAlone { result.append(remainder[open..<runEnd]) }
                    remainder = remainder[runEnd...]
                    continue
                }
            }
            let closer: Character = remainder[open] == "[" ? "]" : remainder[open] == "(" ? ")" : "*"
            guard let close = remainder[open...].firstIndex(of: closer) else { break }

            let before = remainder[..<open].last
            let after =
                remainder.index(after: close) < remainder.endIndex
                ? remainder[remainder.index(after: close)] : nil
            let standsAlone =
                (before == nil || before?.isWhitespace == true)
                && (after == nil || after?.isWhitespace == true || after?.isPunctuation == true)

            let inside = remainder[remainder.index(after: open)..<close]
            let looksLikeAMarker = standsAlone && isMarker(inside)

            result.append(remainder[..<open])
            if !looksLikeAMarker {
                result.append(remainder[open...close])
            }
            remainder = remainder[remainder.index(after: close)...]
        }
        result.append(remainder)

        return result.joined()
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .trimmingWhitespace()
    }
}

extension RawSegment {
    fileprivate func transcriptionSegment(shiftedBy offset: Duration) -> TranscriptionSegment {
        // An empty list falls back to the segment's text; Whisper's leading space on each word is trimmed.
        let spoken = words.flatMap { $0.isEmpty ? nil : $0 }?.map {
            TranscribedWord(
                text: $0.text.trimmingCharacters(in: .whitespaces),
                confidence: $0.probability)
        }
        let kept = spoken.map(RawTranscript.cleaned)
        return TranscriptionSegment(
            // Derived from the words wherever the recogniser reported them, so a removal reaches both.
            text: kept.map { $0.map(\.text).joined(separator: " ") } ?? RawTranscript.cleaned(text),
            start: .seconds(start) + offset,
            end: .seconds(end) + offset,
            words: kept ?? []
        )
    }
}

extension String {
    /// Foundation-free whitespace trim, so this module stays as testable as the core.
    fileprivate func trimmingWhitespace() -> String {
        String(drop(while: \.isWhitespace).reversed().drop(while: \.isWhitespace).reversed())
    }
}
