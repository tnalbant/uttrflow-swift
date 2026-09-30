import Testing

@testable import UttrflowUX
import UttrflowCore

@Suite("The shortcut registry covers every action")
struct ShortcutRegistryTests {
    @Test("gives every action its own descriptor")
    func everyActionHasItsOwnDescriptor() {
        for action in ShortcutAction.allCases {
            #expect(ShortcutRegistry.descriptor(for: action).action == action, "\(action)")
        }
    }

    @Test("claims exactly the actions registered as claimed")
    func claimedMatchesDelivery() {
        let claimedActions = Set(ShortcutRegistry.claimed.map(\.action))
        let deliveredAsClaimed = Set(
            ShortcutRegistry.all
                .filter { $0.delivery == .claimed }
                .map(\.action))

        #expect(claimedActions == deliveredAsClaimed)
    }
}
