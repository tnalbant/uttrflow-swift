// The stages after recognition: dictionary, tidier, message passes and snippets.
import UttrflowAI
import UttrflowCore

extension DictationPipeline {
    /// Runs the dictionary and the tidier over one recognised piece.
    func finish(
        _ heard: Transcription, seeing appContext: AppContext,
        correctionSeeing correctionContext: AppContext, finalPiece: Bool = false,
        recording metrics: any MetricsRecording, for mine: Int
    ) async -> Piece {
        // The dictionary before the tidier: a correction is argued from the sentence as heard.
        let corrected = await correct(heard, seeing: correctionContext, recording: metrics)
        let cleaned = await tidy(
            heard, saying: corrected, seeing: appContext, finalPiece: finalPiece,
            recording: metrics, for: mine)
        return Piece(heard: heard, corrected: corrected, cleaned: cleaned)
    }

    /// Puts the user's own spellings in, leaving the transcript alone if it cannot. §19.
    func correct(
        _ transcription: Transcription, seeing appContext: AppContext,
        recording metrics: any MetricsRecording
    ) async -> CorrectedTranscript {
        do {
            let proposed =
                try await metrics.measuringInTime(.correction, clock: clock) {
                    try await withStageTimeout(StageTimeout.quick, clock: clock) { [corrector] in
                        try await corrector.corrections(for: transcription, seeing: appContext)
                    }
                } ?? []
            // The commonest answer, and not worth rebuilding a string to arrive at itself.
            guard !proposed.isEmpty else { return .unchanged(transcription.text) }
            return DictationCorrection.applying(proposed, to: transcription.text)
        } catch {
            return .unchanged(transcription.text)
        }
    }

    /// Gives the dictionary a joined transcript, keeping only proposals that cross a piece boundary.
    func correctAcrossSeams(
        _ pieces: [Piece], in joined: Piece, seeing appContext: AppContext,
        recording metrics: any MetricsRecording
    ) async -> Piece {
        guard pieces.count > 1 else { return joined }
        let boundaries = pieces.dropLast().reduce(into: [Int]()) { result, piece in
            result.append((result.last ?? 0) + piece.heard.text.spokenWordCount)
        }
        let proposed = await correct(joined.heard, seeing: appContext, recording: metrics).corrections
        let crossings = proposed.filter { correction in
            boundaries.contains {
                correction.wordRange.lowerBound < $0 && correction.wordRange.upperBound > $0
            } && !joined.corrected.corrections.contains { $0.wordRange.overlaps(correction.wordRange) }
        }
        guard !crossings.isEmpty else { return joined }

        var correctedText = joined.corrected.text
        var cleanedText = joined.cleaned.text
        var added: [DictationCorrection] = []
        var shift = 0
        for correction in crossings.sorted(by: { $0.wordRange.lowerBound < $1.wordRange.lowerBound }) {
            let earlier = joined.corrected.corrections.filter {
                $0.wordRange.lowerBound < correction.wordRange.lowerBound
            }
            let priorShift = earlier.reduce(0) {
                $0 + $1.wrote.spokenWords.count - $1.wordRange.count
            }
            let correctedStart = correction.wordRange.lowerBound + priorShift + shift
            let correctedEnd = correction.wordRange.upperBound + priorShift + shift
            let correctedRange = correctedStart..<correctedEnd
            let replacement = correction.wrote.spokenWords
                .map { String(SpokenToken($0).core) }
                .joined(separator: " ")
            let mapped = Self.correction(correction, at: correctedRange, writing: replacement)
            let applied = DictationCorrection.applying([mapped], to: correctedText)
            guard applied.corrections.count == 1 else { continue }
            correctedText = applied.text
            let actual = applied.corrections[0]
            added.append(Self.correction(actual, at: correction.wordRange))
            shift += actual.wrote.spokenWords.count - correction.wordRange.count

            let heardShape = Self.correction(correction, at: correction.wordRange, writing: correction.heard)
            let located = DictationCorrection.locating(
                [heardShape], from: joined.heard.text, in: cleanedText
            ).first?.writtenWordIndex
            if let located {
                let cleanedRange = located..<(located + correction.wordRange.count)
                cleanedText =
                    DictationCorrection.applying(
                        [Self.correction(correction, at: cleanedRange)], to: cleanedText
                    ).text
            }
        }
        guard !added.isEmpty else { return joined }
        return Piece(
            heard: joined.heard,
            corrected: CorrectedTranscript(
                text: correctedText, corrections: joined.corrected.corrections + added),
            cleaned: TransformationResult(
                text: cleanedText, producedBy: joined.cleaned.producedBy,
                cleaning: joined.cleaned.cleaning, entriesTaken: joined.cleaned.entriesTaken))
    }

    static func correction(
        _ correction: DictationCorrection, at range: Range<Int>, writing text: String? = nil
    ) -> DictationCorrection {
        DictationCorrection(
            heard: correction.heard, wrote: text ?? correction.wrote, wordRange: range,
            entryID: correction.entryID, reason: correction.reason,
            heardConfidence: correction.heardConfidence)
    }

    /// Tidies the transcript, falling back to exactly what was said. The only optional stage.
    func tidy(
        _ transcription: Transcription, saying corrected: CorrectedTranscript,
        seeing appContext: AppContext, finalPiece: Bool = false,
        recording metrics: any MetricsRecording, for mine: Int
    ) async -> TransformationResult {
        let text = corrected.text
        // Every piece of a dictation is tidied against the one screen read, so all see one situation.
        let (situation, profile) = tidyingFrame(seeing: appContext)
        let request = TransformationRequest(
            transcription: transcription.saying(corrected), context: appContext,
            profile: profile, situation: situation, scope: .piece)
        if finalPiece { await runningCleaner.reserveFinalPiece(situation) }
        // Not `.rules`: no pass ran over these words, and a record that says otherwise cannot be read.
        let untidied = TransformationResult(text: text, producedBy: .untidied)

        do {
            let tidied = try await metrics.measuringInTime(.transformation, clock: clock) {
                try await withStageTimeout(StageTimeout.transformation, clock: clock) {
                    [cleaner = runningCleaner] in
                    try await cleaner.clean(request)
                }
            }
            // A language model that never answers costs the tidying, never the words.
            guard let tidied else { return untidied }
            // A cancelled dictation's record is not merged into the one now under way.
            if let cleaning = tidied.cleaning { keep(cleaning, for: mine) }
            return tidied
        } catch {
            return untidied
        }
    }

    /// Asks the cleaner for the message's own passes once over the joined pieces; untidied words stay as they were.
    func finishMessage(
        _ joined: Piece, going situation: Situation, seeing appContext: AppContext
    ) async -> Piece {
        guard joined.cleaned.producedBy != .untidied else { return joined }
        let request = TransformationRequest(
            transcription: joined.heard.saying(joined.corrected), context: appContext,
            profile: runningProfile,
            situation: situation)
        let finished = await runningCleaner.finishMessage(joined.cleaned.text, for: request)
        return Piece(
            heard: joined.heard, corrected: joined.corrected,
            cleaned: TransformationResult(
                text: finished, producedBy: joined.cleaned.producedBy,
                cleaning: joined.cleaned.cleaning, entriesTaken: joined.cleaned.entriesTaken))
    }

    /// Expands the user's snippets under the destination's layout, treating a blank expansion as nothing to do.
    func expand(
        _ text: String, matching seamInput: SeamSnippetInput, laidOut layout: LayoutPolicy
    ) async -> ExpandedTranscript {
        do {
            let expanded = try await metrics.measuringInTime(.expansion, clock: clock) {
                try await withStageTimeout(StageTimeout.quick, clock: clock) { [snippets] in
                    try await snippets.expand(seamInput.removingSeamStops())
                }
            }
            guard let expanded, !expanded.text.isBlank else { return .unchanged(text) }
            // A line break is Return in a single-line field, so an expansion's breaks join as the tidier's did.
            let restored = seamInput.restoringUnconsumedStops(in: expanded)
            return layout.contains(.singleLine) ? restored.onOneLine : restored
        } catch {
            return .unchanged(text)
        }
    }
}
