import Foundation
import Testing

@testable import UttrflowCore

@Suite("Secret shape boundary checks", .bug(id: 5732))
struct SecretShapesMutationTests {
    private static let payload = Data((0..<63).map(UInt8.init)).base64EncodedString()

    @Test("rejects data URIs with invalid MIME components or parameters")
    func invalidMIME() {
        let invalidComponent = "data:ima:ge/png;base64,\(Self.payload)"
        let invalidParameter = "data:text/plain;charset;base64,\(Self.payload)"

        #expect(SecretShapes.matches(invalidComponent))
        #expect(SecretShapes.matches(invalidParameter))
    }

    @Test("rejects a data URI whose source attribute has mismatched quotes")
    func mismatchedSourceQuotes() {
        let text = "src=\"data:image/png;base64,\(Self.payload)'"

        #expect(SecretShapes.matches(text))
    }

    @Test("rejects a data URI whose CSS wrapper has mismatched quotes")
    func mismatchedCSSQuotes() {
        let text = "background:url(\"data:image/png;base64,\(Self.payload)')"

        #expect(SecretShapes.matches(text))
    }

    @Test("does not exempt joined words with an overlong numeric suffix")
    func joinedWordNumericSuffix() {
        #expect(SecretShapes.matches("northstar-riverbed-123abc"))
    }

    @Test("does not treat a quoted path with a generated-looking component as a secret")
    func quotedPath() {
        let token = "K9x$Qz7" + "Tr2Bn8LmVa"
        let path = "\"/Volumes/Backup Drive/photos/2026/\(token)\""

        #expect(!SecretShapes.matches(path))
    }

    @Test("does not treat an opaque known-scheme address as a secret")
    func knownURIScheme() {
        let address = "urn:example:" + "Q7Vn2mR8xL4pK9cD"

        #expect(!SecretShapes.matches(address))
    }

    @Test("ordinary short and non-ASCII text stays outside the entropy rule")
    func shortAndNonASCIITokens() {
        #expect(!SecretShapes.matches("x"))
        #expect(!SecretShapes.matches("☃"))
    }
}
