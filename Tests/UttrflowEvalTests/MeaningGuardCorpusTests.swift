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

    @Test("as-spoken chat corpus keeps dialect verb forms")
    func corpusKeepsAsSpokenVerbForms() {
        let guarder = MeaningPreservationGuard()
        let dialectCases = EvaluationCorpus.all.filter { $0.id.hasPrefix("message-dialect-") }
        #expect(dialectCases.count == 4)
        for sample in dialectCases {
            #expect(
                guarder.verdict(
                    draft: Draft(text: sample.spoken), rewritten: sample.expected,
                    grammar: DestinationFormatter.standard(for: sample.situation).grammar
                ).isAccepted,
                "\(sample.id) should preserve its spoken form"
            )
        }
    }

}
