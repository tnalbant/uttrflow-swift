import Testing

@testable import UttrflowCore

@Suite("SentenceCount")
struct SentenceCountTests {
    @Test(
        "counts danda and double danda as sentence endings",
        arguments: [
            ("वाक्य।", 1), ("वाक्य॥", 1), ("पहला वाक्य। दूसरा वाक्य॥", 2),
        ])
    func devanagariSentenceEndings(text: String, expected: Int) {
        #expect(SentenceCount.of(text) == expected)
    }
}
