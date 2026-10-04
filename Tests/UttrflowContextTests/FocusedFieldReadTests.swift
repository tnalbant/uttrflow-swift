import Foundation
import Testing

@testable import UttrflowContext

struct FocusedFieldReadTests {
    private static let plain = FieldNames(
        role: "AXTextField", subrole: nil, identifier: nil, placeholder: nil, description: nil)

    private static func field(_ answers: [String: FieldAnswer]) -> Node {
        Node(id: 1, role: "AXTextField", answers: answers)
    }

    private static func read(
        _ node: Node, names: FieldNames = plain, at selection: NSRange? = NSRange(location: 2, length: 0),
        log: MessageLog? = nil
    ) -> FieldText {
        FocusedFieldRead.text(
            of: node, in: FakeTree(root: node, messages: log), names: names, at: selection)
    }

    @Test func shortFieldIsReadWholeInTwoMessages() {
        let log = MessageLog()
        let text = Self.read(
            Self.field(["AXNumberOfCharacters": .value(5), "AXValue": .value("hello")]), log: log)
        #expect(text.value == "hello")
        #expect(text.selection == NSRange(location: 2, length: 0))
        #expect(log.asked == ["AXNumberOfCharacters", "AXValue"])
    }

    @Test func declaredSecureFieldIsAskedNothing() {
        let log = MessageLog()
        let names = FieldNames(
            role: "AXSecureTextField", subrole: nil, identifier: nil, placeholder: nil, description: nil)
        let text = Self.read(Self.field(["AXValue": .value("hunter2")]), names: names, log: log)
        #expect(text.isSecure)
        #expect(text.value == nil)
        #expect(log.asked.isEmpty)
    }

    @Test func maskedValueIsSecure() {
        let text = Self.read(Self.field(["AXNumberOfCharacters": .value(4), "AXValue": .value("••••")]))
        #expect(text.isSecure)
    }

    @Test(arguments: [FieldAnswer.noValue, .unsupported, .cannotComplete, .timedOut])
    func refusedCountReadsNoValue(refusal: FieldAnswer) {
        let log = MessageLog()
        let text = Self.read(
            Self.field(["AXNumberOfCharacters": refusal, "AXValue": .value("hello")]), log: log)
        #expect(text.value == nil)
        #expect(log.asked == ["AXNumberOfCharacters"])
    }

    @Test(arguments: [FieldAnswer.noValue, .unsupported, .cannotComplete, .timedOut])
    func refusedRangeOnALongFieldNeverFallsBackToTheWholeValue(refusal: FieldAnswer) {
        let long = String(repeating: "a", count: ValueWindow.unitsBefore + ValueWindow.unitsAfter + 10)
        let log = MessageLog()
        let text = Self.read(
            Self.field([
                "AXNumberOfCharacters": .value(long.utf16.count), "AXValue": .value(long),
                "AXStringForRange": refusal,
            ]), at: NSRange(location: long.utf16.count, length: 0), log: log)
        #expect(text.value == nil)
        #expect(log.asked == ["AXNumberOfCharacters", "AXStringForRange"])
    }

    @Test func longFieldIsReadByRangeAroundTheCaret() {
        let long = String(repeating: "a", count: ValueWindow.unitsBefore + ValueWindow.unitsAfter + 10)
        let caret = long.utf16.count
        let text = Self.read(
            Self.field(["AXNumberOfCharacters": .value(caret), "AXValue": .value(long)]),
            at: NSRange(location: caret, length: 0))
        #expect(text.value?.utf16.count == ValueWindow.unitsBefore)
        #expect(text.selection == NSRange(location: ValueWindow.unitsBefore, length: 0))
    }

    @Test func namesAreAskedTogetherAndReadInOrder() {
        let node = Self.field([
            "AXRole": .value("AXTextField"), "AXPlaceholderValue": .value("Password"),
        ])
        let names = FocusedFieldRead.names(of: node, in: FakeTree(root: node))
        #expect(names.role == "AXTextField")
        #expect(names.placeholder == "Password")
        #expect(names.subrole == nil)
        #expect(names.isDeclaredSecure)
    }

    @Test func classifyKeepsEveryRefusalApart() {
        func classify(_ code: Int32, _ value: Any? = nil, elapsed: Double = 0) -> FieldAnswer {
            FieldAnswer.classify(code: code, value: value, elapsedSeconds: elapsed, timeoutSeconds: 1)
        }
        #expect(classify(0, "x") == .value("x"))
        #expect(classify(0) == .noValue)
        #expect(classify(-25212) == .noValue)
        #expect(classify(-25204) == .cannotComplete)
        #expect(classify(-25204, elapsed: 2) == .timedOut)
        #expect(classify(-25205) == .unsupported)
    }
}
