import Foundation
import Testing

@testable import UttrflowPredict

@Suite("Quiet mode behavior for generated suggestions")
struct SuggestionSessionQuietModeTests {
    private let field = Surface(bundleIdentifier: "com.apple.Terminal", role: "AXTextArea")

    @Test("expandGenerated returns nil when isQuiet is true")
    func expandGeneratedReturnsNilWhenQuiet() {
        var session = SuggestionSession()
        let context = PredictionContext(typed: "git c")
        let turn = session.turn(in: field, at: context, isQuiet: true)
        
        // First, draw a generated suggestion
        let query: SuggestionQuery
        switch turn.step {
        case .query(let q):
            query = q
        case .settled:
            Issue.record("Expected a query")
            return
        }
        
        let completions = ["git commit -m"]
        let update = session.resolveGenerated(
            completions, for: query, elapsedMilliseconds: 100, whenEmpty: .nothingOffered
        )
        
        #expect(update != nil)
        #expect(session.suggestion == .certain("git commit -m"))
        
        // Now try to expand with alternatives - should return nil in Quiet mode
        let alternatives = ["git commit --amend", "git commit -m --signoff"]
        let expanded = session.expandGenerated(alternatives, for: query)
        
        #expect(expanded == nil)
    }

    @Test("expandGenerated returns update when isQuiet is false")
    func expandGeneratedReturnsUpdateWhenNotQuiet() {
        var session = SuggestionSession()
        let context = PredictionContext(typed: "git c")
        let turn = session.turn(in: field, at: context, isQuiet: false)
        
        // First, draw a generated suggestion
        let query: SuggestionQuery
        switch turn.step {
        case .query(let q):
            query = q
        case .settled:
            Issue.record("Expected a query")
            return
        }
        
        let completions = ["git commit -m"]
        let update = session.resolveGenerated(
            completions, for: query, elapsedMilliseconds: 100, whenEmpty: .nothingOffered
        )
        
        #expect(update != nil)
        #expect(session.suggestion == .certain("git commit -m"))
        
        // Now try to expand with alternatives - should return update when not Quiet
        let alternatives = ["git commit --amend", "git commit -m --signoff"]
        let expanded = session.expandGenerated(alternatives, for: query)
        
        #expect(expanded != nil)
        if case .choice(let leader, _) = expanded?.suggestion {
            #expect(leader == "git commit -m")
        }
    }
}
