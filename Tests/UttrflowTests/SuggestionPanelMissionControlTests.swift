import AppKit
import Testing

@testable import Uttrflow

@MainActor
@Suite("Suggestion panel in Mission Control")
struct SuggestionPanelMissionControlTests {
    @Test("the ghost panel hides in window overviews")
    func panelUsesTransientCollectionBehavior() {
        let behavior = SuggestionPanelController.shared.window.collectionBehavior

        #expect(behavior.contains(.transient))
        #expect(!behavior.contains(.stationary))
    }
}
