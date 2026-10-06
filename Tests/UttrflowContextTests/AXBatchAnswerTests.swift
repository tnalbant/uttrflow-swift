import ApplicationServices
import Testing

@testable import UttrflowContext

struct AXBatchAnswerTests {
    @Test("A failed outer batch keeps successful positions and each slot's AX error.")
    func preservesPartialAnswers() throws {
        var unsupported = AXError.attributeUnsupported
        let errorValue = try #require(AXValueCreate(.axError, &unsupported))
        let values: [AnyObject] = ["AXTextField" as CFString, errorValue, kCFNull]

        let answers = FocusedFieldReader.AXElementTree.decodeBatch(
            values, count: 3, error: .cannotComplete, elapsedSeconds: 0.01)

        #expect(answers[0].string == "AXTextField")
        #expect(answers[1] == .unsupported)
        #expect(answers[2] == .noValue)
    }

    @Test("Absent batch positions are classified without requesting the attribute again.")
    func missingPositionsBecomeNoValue() {
        let answers = FocusedFieldReader.AXElementTree.decodeBatch(
            ["AXTextField" as CFString], count: 2, error: .success, elapsedSeconds: 0)

        #expect(answers[0].string == "AXTextField")
        #expect(answers[1] == .noValue)
    }

    @Test("The cached surroundings batch keeps values around absent slots.")
    func padsWithoutDiscardingPartialValues() {
        let values = FocusedFieldReader.Answers.padded(["AXTextField" as CFString], to: 2)

        #expect(values.count == 2)
        #expect(values[0] as? String == "AXTextField")
        #expect(CFGetTypeID(values[1]) == CFNullGetTypeID())
    }

    @Test("A batch cannot-complete at its messaging timeout remains timed out.")
    func timedOutSlotsStayTimedOut() throws {
        var cannotComplete = AXError.cannotComplete
        let errorValue = try #require(AXValueCreate(.axError, &cannotComplete))

        let answers = FocusedFieldReader.AXElementTree.decodeBatch(
            [errorValue], count: 1, error: .cannotComplete, elapsedSeconds: 1)

        #expect(answers == [.timedOut])
    }

    @Test("A partial batch with no role cannot expose element text.")
    func missingRoleFailsClosed() {
        var fetched = Array(
            repeating: kCFNull as AnyObject, count: FocusedFieldReader.Answers.attributes.count)
        fetched[FocusedFieldReader.Answers.attributes.firstIndex(of: kAXTitleAttribute)!] =
            "private field title" as CFString
        let answers = FocusedFieldReader.Answers(AXUIElementCreateSystemWide(), fetched: fetched)

        #expect(answers.isSecure)
        #expect(answers.text == nil)
    }

    @Test("A failed subrole slot cannot expose text from a text field.")
    func unreadableSubroleFailsClosed() throws {
        var cannotComplete = AXError.cannotComplete
        let errorValue = try #require(AXValueCreate(.axError, &cannotComplete))
        var fetched = Array(
            repeating: kCFNull as AnyObject, count: FocusedFieldReader.Answers.attributes.count)
        fetched[FocusedFieldReader.Answers.attributes.firstIndex(of: kAXRoleAttribute)!] =
            "AXTextField" as CFString
        fetched[FocusedFieldReader.Answers.attributes.firstIndex(of: kAXSubroleAttribute)!] =
            errorValue
        fetched[FocusedFieldReader.Answers.attributes.firstIndex(of: kAXTitleAttribute)!] =
            "private field title" as CFString
        let answers = FocusedFieldReader.Answers(AXUIElementCreateSystemWide(), fetched: fetched)

        #expect(answers.isSecure)
        #expect(answers.text == nil)
    }
}
