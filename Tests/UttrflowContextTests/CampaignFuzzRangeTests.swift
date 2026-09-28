// Campaign fuzz: AccessibilityRange over every hostile range. Not for commit.
import Foundation
import Testing

@testable import UttrflowContext

@Suite("CampaignFuzz accessibility range")
struct CampaignFuzzRangeTests {
    @Test("ends, selections and widened ranges never trap")
    func ranges() {
        let edges = [Int.min, Int.min + 1, -2, -1, 0, 1, 2, Int(Int32.max), NSNotFound - 1, NSNotFound, Int.max - 1, Int.max]
        var generator = SystemRandomNumberGenerator()
        var checked = 0
        for index in 0..<2_000_000 {
            let location = index < edges.count * edges.count ? edges[index / edges.count] : (Bool.random() ? edges.randomElement()! &+ Int.random(in: -3...3) : Int.random(in: Int.min...Int.max, using: &generator))
            let length = index < edges.count * edges.count ? edges[index % edges.count] : (Bool.random() ? edges.randomElement()! &+ Int.random(in: -3...3) : Int.random(in: Int.min...Int.max, using: &generator))
            if let end = AccessibilityRange.end(location: location, length: length) {
                #expect(end >= location)
                #expect(location != NSNotFound)
            }
            if let selection = AccessibilityRange.selection(location: location, length: length) {
                #expect(selection.lowerBound == location)
            }
            let widened = AccessibilityRange.widenedForStyle(CFRange(location: location, length: length))
            if length > 0 { #expect(widened.location == location) } else { #expect(widened.location >= 0 && widened.length == 1) }
            checked += 1
        }
        print("CAMPAIGN accessibilityRange iterations=\(checked)")
    }
}
