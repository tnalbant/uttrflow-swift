public import UttrflowCore

extension CleaningPipeline {
    /// Every pass in the shipped order, for plain text at a caret that says nothing.
    public static let standard = standard(for: .standard(for: .plain), situation: .unknown)

    /// The passes a language model is handed the result of, which are the piece's; the message's are finished after it.
    public static func beforeModel(
        for formatter: DestinationFormatter, situation: Situation, steps: CleaningSteps = .default
    ) -> CleaningPipeline {
        piece(
            numbers: formatter.numbers, digits: formatter.digits, layout: formatter.layout,
            insertionPoint: situation.insertion, destination: formatter.destination,
            precedingText: situation.insertion.precedingText, documentName: situation.app.documentName,
            steps: steps)
    }

    /// Every pass the user has left on over a whole message, in the shipped order: the piece's, then the message's.
    public static func standard(
        for formatter: DestinationFormatter, situation: Situation, steps: CleaningSteps = .default
    ) -> CleaningPipeline {
        CleaningPipeline(
            passes: piece(
                numbers: formatter.numbers, digits: formatter.digits, insertionPoint: situation.insertion,
                destination: formatter.destination, precedingText: situation.insertion.precedingText,
                documentName: situation.app.documentName, steps: steps
            ).passes
                + [SpelledInitialismPass()]
                + message(for: formatter, situation: situation).passes)
    }

    /// The passes that are right on any piece of a message, which is why no casing or stop policy can reach them.
    public static func piece(
        numbers: NumberPolicy, digits: DigitGrouping, layout: LayoutPolicy = [.paragraphs, .lists],
        insertionPoint: InsertionPoint = .unknown, destination: Destination = .plain,
        precedingText: String? = nil, documentName: String? = nil,
        steps: CleaningSteps = .default
    ) -> CleaningPipeline {
        var cleanings: [any CleaningPass] = [
            FillersPass(), RepeatedPhrasePass(), StammersPass(), SelfCorrectionPass(),
            // Spoken punctuation must mark a stop before LayoutWordsPass checks for a break after it.
            SpokenPunctuationPass(destination: destination),
            LayoutWordsPass(layout: layout, insertionPoint: insertionPoint),
            NumberFormsPass(policy: numbers, digits: digits),
            ContractionsPass(), SpelledInitialismPass(), SpacingPass(),
        ]
        if destination == .codeEditor,
            !CodeCommentContext.isComment(precedingText: precedingText, documentName: documentName),
            let layoutPosition = cleanings.firstIndex(where: { $0.id == .layoutWords })
        {
            cleanings.insert(CodeEditorCommandsPass(), at: layoutPosition)
        }
        return CleaningPipeline(passes: cleanings.filter { steps.runs($0.id) })
    }

    /// The passes that finish a model's answer to a whole message: the caret's echo taken back, then the message's.
    public static func afterModel(
        for formatter: DestinationFormatter, situation: Situation, heard: String? = nil,
        spoken: String? = nil
    ) -> CleaningPipeline {
        CleaningPipeline(
            passes: afterModelPiece(situation: situation, heard: heard, spoken: spoken).passes
                + [SpelledInitialismPass()]
                + message(for: formatter, situation: situation, heard: heard).passes)
    }

    /// What finishes a model's answer to one piece before the final message-wide passes run.
    public static func afterModelPiece(
        situation: Situation, heard: String? = nil, spoken: String? = nil
    ) -> CleaningPipeline {
        CleaningPipeline(passes: [
            SpokenPunctuationPass(destination: situation.destination),
            CaretEchoPass(
                state: situation.insertion.sentenceState, precedingText: situation.insertion.precedingText,
                spokenText: heard),
            CaretCloserPass(precedingText: situation.insertion.precedingText, spokenText: spoken),
        ])
    }

    /// The two passes asked once of a whole message, the first word and the final stop; `heard` is what `.asSpoken` copies.
    public static func message(
        for formatter: DestinationFormatter, situation: Situation, heard: String? = nil
    ) -> CleaningPipeline {
        CleaningPipeline(passes: [
            SentenceBoundaryPass(),
            FirstWordPass(
                policy: formatter.firstWord, state: situation.insertion.sentenceState,
                onScreen: situation.app.textOnScreen, heard: heard,
                capitaliseCalendarWords: formatter.firstWord == .fromInsertionPoint
                    && formatter.destination != .codeEditor),
            TerminalStopPass(
                policy: terminalStop(formatter, in: situation), layout: formatter.layout,
                insertionPoint: situation.insertion, destination: formatter.destination),
        ])
    }

    /// The typed whole-text rules that apply once the pieces have been laid out.
    public static func wholeText(
        for formatter: DestinationFormatter, situation: Situation, heard: String? = nil
    ) -> CleaningPipeline {
        message(for: formatter, situation: situation, heard: heard)
    }

    /// The formatter's stop policy, except a code editor takes `.always` when the caret sits in a comment.
    private static func terminalStop(
        _ formatter: DestinationFormatter, in situation: Situation
    ) -> TerminalStopPolicy {
        guard formatter.destination == .codeEditor else { return formatter.terminalStop }
        let inComment = CodeCommentContext.isComment(
            precedingText: situation.insertion.precedingText, documentName: situation.app.documentName)
        return inComment ? .always : formatter.terminalStop
    }
}

extension AppContext {
    /// The strings read off the screen a name can be sighted in: title, selection and the text at the caret.
    var textOnScreen: [String] {
        [documentName, selectedText, precedingText, followingText].compactMap { $0 }
    }
}
