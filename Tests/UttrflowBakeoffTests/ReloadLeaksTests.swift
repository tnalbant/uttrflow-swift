import ArgumentParser
import Testing
@testable import uttrflow_bakeoff

struct ReloadLeaksTests {
    @Test("checkpoints must be positive before the median is calculated")
    func checkpointsMustBePositive() throws {
        #expect(try ReloadLeaks.parseCheckpoints("1,5,20") == [1, 5, 20])
        #expect(throws: ValidationError.self) {
            try ReloadLeaks.parseCheckpoints("0")
        }
        #expect(throws: ValidationError.self) {
            try ReloadLeaks.parseCheckpoints("1,0,2")
        }
    }

    @Test("checkpoints must remain ascending whole numbers")
    func checkpointsMustBeAscendingWholeNumbers() {
        #expect(throws: ValidationError.self) {
            try ReloadLeaks.parseCheckpoints("5,1")
        }
        #expect(throws: ValidationError.self) {
            try ReloadLeaks.parseCheckpoints("1,x,5")
        }
        #expect(throws: ValidationError.self) {
            try ReloadLeaks.parseCheckpoints("1,,5")
        }
        #expect(throws: ValidationError.self) {
            try ReloadLeaks.parseCheckpoints(",1,5")
        }
        #expect(throws: ValidationError.self) {
            try ReloadLeaks.parseCheckpoints("1,5,")
        }
    }
}
