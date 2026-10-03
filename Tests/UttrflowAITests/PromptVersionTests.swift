import UttrflowCore
import Testing

@testable import UttrflowAI

/// The prompt's version is computed from what the model reads, so no wording change can keep an old version.
@Suite("PromptVersion")
struct PromptVersionTests {
    private let standard = PromptBuilder.standard
    private let schema = PromptBuilder.answerSchema

    /// The standard builder with one block's rules or examples replaced.
    private func editing(_ id: PromptBlockID, _ edit: (PromptBlock) -> PromptBlock) -> PromptBuilder {
        var blocks = standard.blocks
        if let block = blocks[id] { blocks[id] = edit(block) }
        return PromptBuilder(
            contract: standard.contract, contractExamples: standard.contractExamples, blocks: blocks)
    }

    @Test("is the shipping prompt's fingerprint: twelve hex digits, the same on every reading")
    func shape() {
        #expect(PromptBuilder.version == standard.version(answeringIn: schema))
        #expect(PromptBuilder.version.count == 12)
        #expect(PromptBuilder.version.allSatisfy { $0.isHexDigit })
    }

    @Test("changes when one character of the contract changes")
    func contract() {
        let edited = PromptBuilder(
            contract: standard.contract + ".", contractExamples: standard.contractExamples,
            blocks: standard.blocks)
        #expect(edited.version(answeringIn: schema) != PromptBuilder.version)
    }

    @Test("changes when one character of a shared example changes")
    func contractExample() {
        var examples = standard.contractExamples
        let first = examples[0]
        examples[0] = WorkedExample(spoken: first.spoken, cleaned: first.cleaned + " ")
        let edited = PromptBuilder(
            contract: standard.contract, contractExamples: examples, blocks: standard.blocks)
        #expect(edited.version(answeringIn: schema) != PromptBuilder.version)
    }

    @Test(
        "changes when one character of any block's rules or examples changes",
        arguments: Array(PromptBlocks.standard.keys))
    func block(_ id: PromptBlockID) {
        let rules = editing(id) { PromptBlock(id: $0.id, rules: $0.rules + ".", examples: $0.examples) }
        let examples = editing(id) {
            PromptBlock(
                id: $0.id, rules: $0.rules,
                examples: $0.examples + [WorkedExample(spoken: "a", cleaned: "A.")])
        }
        #expect(rules.version(answeringIn: schema) != PromptBuilder.version)
        #expect(examples.version(answeringIn: schema) != PromptBuilder.version)
    }

    @Test("changes when one character of the answer's schema changes, and the schema carries the guide")
    func answerSchema() {
        #expect(schema.contains(PromptContract.answerGuide))
        #expect(standard.version(answeringIn: schema + " ") != PromptBuilder.version)
    }

    @Test("covers every situation label, since a renamed label changes what the model reads")
    func labels() {
        let expected = [
            AppContextDescriber.label, AppContextDescriber.selectionLabel, PromptBuilder.caretLabel,
            PromptBuilder.doubtfulLabel, PromptBuilder.preservedLabel,
        ]
        #expect(Set(PromptBuilder.labels) == Set(expected))
    }

    @Test("prefixes each part with its length, so moving text between parts changes the fingerprint")
    func partsDoNotRun() {
        #expect(PromptBuilder.fingerprint(["ab", "c"]) != PromptBuilder.fingerprint(["a", "bc"]))
        #expect(PromptBuilder.fingerprint(["ab", "c"]) == PromptBuilder.fingerprint(["ab", "c"]))
    }
}
