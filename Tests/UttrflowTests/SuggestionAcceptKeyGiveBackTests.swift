import Testing
import UttrflowPredict

@testable import Uttrflow

@Suite("Giving a failed suggestion's accept key back")
struct SuggestionAcceptKeyGiveBackTests {
    @Test("a successful insertion keeps the accept key")
    @MainActor
    func successfulTakeDoesNotReturnTab() async {
        var attempts = 0
        let keyToReturn = await SuggestionCoordinator.acceptKeyToReturnIfTakeFails(
            UttrflowPredict.KeyStroke(.tab)
        ) {
            attempts += 1
            return true
        }

        #expect(attempts == 1)
        #expect(keyToReturn == nil)
    }

    @Test("a failed insertion returns the swallowed Tab exactly once")
    @MainActor
    func failedTakeReturnsTabOnce() async {
        var attempts = 0
        let keyToReturn = await SuggestionCoordinator.acceptKeyToReturnIfTakeFails(
            UttrflowPredict.KeyStroke(.tab)
        ) {
            attempts += 1
            return false
        }
        var posted: [UttrflowPredict.KeyStroke] = []
        if let keyToReturn { posted.append(keyToReturn) }

        #expect(attempts == 1)
        #expect(posted == [UttrflowPredict.KeyStroke(.tab)])
    }
}
