// Campaign fuzz: secret and card-number detection on random and adversarial strings. Not for commit.
import Foundation
import Testing

@testable import UttrflowClipboard

private struct CampaignRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite("CampaignFuzz secrets", .serialized)
struct CampaignFuzzSecretTests {
    private static let pieces: [String] = [
        "a", "Z", "0", "9", " ", "-", ".", "/", ":", "_", "=", "+", "@", "\"", "'", "\n", "\r\n", "\t", ",", ";",
        "sk-", "sk-ant-", "pk_live_", "ghp_", "github_pat_", "glpat-", "xoxb-", "AKIA", "AIza", "npm_", "SG.",
        "eyJ", "://", "https://", "user:pass@", "password", "API_KEY", "token", "secret", "pwd", ": ", "= ",
        "-----BEGIN", "4111", "1111", "5555", "3782", "0000", "٣", "５", "é", "e\u{301}", "🇮🇳", "👩‍💻", "\u{0}",
        "\u{FEFF}", "\u{2028}", "ﬀ", "ß", "İ", "~/", "/Users/", "0x", "deadbeef",
    ]

    private func random(_ rng: inout CampaignRNG, maxPieces: Int) -> String {
        var text = ""
        for _ in 0..<Int.random(in: 0...maxPieces, using: &rng) {
            if Int.random(in: 0...3, using: &rng) == 0 {
                text.unicodeScalars.append(Unicode.Scalar(UInt32.random(in: 0x20...0x2FFF, using: &rng)) ?? "x")
            } else {
                text += Self.pieces.randomElement(using: &rng)!
            }
        }
        return text
    }

    @Test("millions of random strings: no trap, stable answers, planted secrets found", .timeLimit(.minutes(60)))
    func randomStrings() {
        var rng = CampaignRNG(state: 0x5EED_0301)
        let count = Int(ProcessInfo.processInfo.environment["CAMPAIGN_SECRET_COUNT"] ?? "") ?? 1_000_000
        var positives = 0
        var slowest: Duration = .zero
        var slowestText = ""
        let clock = ContinuousClock()
        for _ in 0..<count {
            let text = random(&rng, maxPieces: 24)
            var answer = false
            let took = clock.measure { answer = SecretShapes.matches(text) }
            if took > slowest {
                slowest = took
                slowestText = text
            }
            if answer { positives += 1 }
            _ = ClipKindDetector.kind(of: text)
        }
        // Planted: a card number between spaces inside letters, and a PEM header anywhere.
        var missedCards = 0
        for _ in 0..<20_000 {
            let left = String((0..<Int.random(in: 0...20, using: &rng)).map { _ in "abcdefgh ".randomElement(using: &rng)! })
            let right = String((0..<Int.random(in: 0...20, using: &rng)).map { _ in "abcdefgh ".randomElement(using: &rng)! })
            let card = ["4111 1111 1111 1111", "4111111111111111", "5555-5555-5555-4444", "378282246310005"].randomElement(using: &rng)!
            if !SecretShapes.matches(left + " " + card + " " + right) { missedCards += 1 }
            #expect(SecretShapes.matches(left + "-----BEGIN" + right))
        }
        print("CAMPAIGN secretRandom count=\(count) positives=\(positives) slowest=\(slowest) missedCards=\(missedCards)")
        print("CAMPAIGN secretRandom slowestTextLength=\(slowestText.utf8.count)")
        #expect(missedCards == 0)
    }

    @Test("the whole classifier on adversarial families", .timeLimit(.minutes(60)))
    func kindScaling() {
        let families: [(String, (Int) -> String)] = [
            ("letters", { String(repeating: "a", count: $0) }),
            ("hexNoSpaces", { String(repeating: "0123456789abcdef", count: $0 / 16) }),
            ("slashes", { String(repeating: "a/", count: $0 / 2) }),
            ("tildePath", { "~/" + String(repeating: "ab/", count: $0 / 3) }),
            ("httpNoSpace", { "https://" + String(repeating: "a", count: $0) }),
            ("hashes", { String(repeating: "#", count: $0) }),
            ("braces", { String(repeating: "{(", count: $0 / 2) }),
            ("rgbOpen", { String(repeating: "rgb(", count: $0 / 4) }),
            ("importLines", { String(repeating: "import a\n", count: $0 / 9) }),
            ("digitsDots", { String(repeating: "1.", count: $0 / 2) }),
        ]
        let clock = ContinuousClock()
        for (name, make) in families {
            var line = "CAMPAIGN kindScaling \(name)"
            for size in [2_000, 8_000, 32_000] {
                let text = make(size)
                let took = clock.measure { _ = ClipKindDetector.kind(of: text) }
                let seconds = Double(took.components.seconds) + Double(took.components.attoseconds) / 1e18
                line += " \(size)=\(String(format: "%.4f", seconds))s"
                if seconds > 30 { line += " (stopped)"; break }
            }
            print(line)
        }
    }

    @Test("adversarial families scale linearly", .timeLimit(.minutes(60)))
    func adversarialScaling() {
        let families: [(String, (Int) -> String)] = [
            ("letters", { String(repeating: "a", count: $0) }),
            ("hexNoSpaces", { String(repeating: "0123456789abcdef", count: $0 / 16) }),
            ("dnaLike", { String(repeating: "ACGT", count: $0 / 4) }),
            ("dottedLetters", { String(repeating: "ab.c-", count: $0 / 5) }),
            ("pwdEquals", { String(repeating: "pwd=", count: $0 / 4) + " x" }),
            ("tokenColon", { String(repeating: "token:", count: $0 / 6) + " x" }),
            ("eyJrepeat", { String(repeating: "eyJa", count: $0 / 4) }),
            ("schemeNoAt", { String(repeating: "a://b:c", count: $0 / 7) }),
            ("digits", { String(repeating: "1", count: $0) }),
            ("digitGroups", { String(repeating: "4111 ", count: $0 / 5) }),
            ("skDash", { String(repeating: "sk-abc", count: $0 / 6) }),
            ("spacesWords", { String(repeating: "hello ", count: $0 / 6) }),
        ]
        let clock = ContinuousClock()
        var quadratic: [String] = []
        for (name, make) in families {
            var previous: Double?
            var line = "CAMPAIGN secretScaling \(name)"
            for size in [2_000, 4_000, 8_000, 16_000] {
                let text = make(size)
                let took = clock.measure { _ = SecretShapes.matches(text) }
                let seconds = Double(took.components.seconds) + Double(took.components.attoseconds) / 1e18
                line += " \(size)=\(String(format: "%.4f", seconds))s"
                if let previous, previous > 0.02, seconds / previous > 3.0, size == 16_000 {
                    quadratic.append(name)
                }
                previous = seconds
                if seconds > 20 {
                    line += " (stopped)"
                    quadratic.append(name)
                    break
                }
            }
            print(line)
        }
        print("CAMPAIGN secretScaling superlinear=\(quadratic)")
        #expect(quadratic.isEmpty, "superlinear families: \(quadratic)")
    }
}
