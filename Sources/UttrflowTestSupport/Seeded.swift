// The one seeded generator every randomised test draws from, and the seed policy that replays a failure.
import Foundation

/// A fixed-seed generator, so every generated case is the same on every run and a failure names its seed.
public struct Seeded: RandomNumberGenerator, CustomStringConvertible {
    /// The environment variable that replaces a test's fixed seeds with the one seed to replay.
    public static let seedVariable = "UTTRFLOW_SEED"

    /// The seed this generator started from, so a failure message can name it.
    public let seed: Int

    /// The generator's whole state, which the seed alone sets.
    private var state: UInt64

    /// A generator that always produces the same sequence for the same seed.
    public init(seed: Int) {
        self.seed = seed
        // The multiply spreads small seeds apart and the low bit keeps xorshift out of its zero fixed point.
        state = (UInt64(truncatingIfNeeded: seed) &* 0x9E37_79B9_7F4A_7C15) | 1
    }

    /// `seed=<n>`, the form a failure message prints and `UTTRFLOW_SEED` takes back.
    public var description: String { "seed=\(seed)" }

    /// The next value in the sequence.
    public mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    /// One of the values, chosen uniformly.
    public mutating func pick<Value>(_ values: [Value]) -> Value {
        values[Int.random(in: 0..<values.count, using: &self)]
    }

    /// Whether an event with this probability happens this time.
    public mutating func chance(_ probability: Double) -> Bool {
        Double.random(in: 0..<1, using: &self) < probability
    }

    /// The seeds a property test runs: its fixed ones, or only the seed `UTTRFLOW_SEED` names.
    public static func seeds(
        _ fixed: some Sequence<Int>, environment: [String: String]? = nil
    ) -> [Int] {
        let environment = environment ?? ProcessInfo.processInfo.environment
        guard let replay = environment[seedVariable].flatMap({ Int($0) }) else { return Array(fixed) }
        return [replay]
    }
}
