import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowEval

@Suite("Meaning guard over the cleanup corpus")
struct MeaningGuardCorpusTests {
    @Test("expected tidy-ups do not relocate a negation")
    func expectedTidyUpsKeepNegationPlacement() {
        let guarder = MeaningPreservationGuard()
        for sample in EvaluationCorpus.all {
            let draft = CleaningPipeline.standard.run(Draft(keepingLineBreaks: sample.spoken))
            if case .rejected(_, let kind) = guarder.verdict(draft: draft, rewritten: sample.expected) {
                #expect(kind != .negationMoved, "\(sample.id) should not move a negation")
            }
        }
    }

    @Test("the cleanup corpus keeps Indian grouping as written")
    func corpusKeepsIndianGrouping() {
        for sample in EvaluationCorpus.all where sample.id.hasPrefix("indian-grouping-") {
            #expect(
                MeaningPreservationGuard.changedIndianGrouping(
                    original: sample.spoken, rewritten: sample.expected
                ) == nil,
                "\(sample.id) changes its numeric grouping"
            )
        }
    }

    @Test("as-spoken chat examples keep dialect verb forms")
    func asSpokenExamplesKeepDialectVerbForms() {
        let guarder = MeaningPreservationGuard()
        let examples = [
            ("we was just talking about you", "We was just talking about you"),
            ("they was at the shop", "They was at the shop"),
            ("i seen it yesterday", "I seen it yesterday"),
            ("he come by yesterday", "He come by yesterday"),
        ]
        #expect(examples.count == 4)
        for (spoken, expected) in examples {
            #expect(
                guarder.verdict(
                    draft: Draft(text: spoken), rewritten: expected,
                    grammar: DestinationFormatter.standard(for: .messaging).grammar
                ).isAccepted,
                "\(spoken) should preserve its spoken form"
            )
        }
    }

}
