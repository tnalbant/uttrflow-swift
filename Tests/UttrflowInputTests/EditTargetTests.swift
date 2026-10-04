import Testing

@testable import UttrflowCore
@testable import UttrflowInput

@Suite("Editing a recorded insertion by its range")
struct EditTargetTests {
    static let field = FieldIdentity(processIdentifier: 7, windowNumber: 1, element: 3)
    static let other = FieldIdentity(processIdentifier: 7, windowNumber: 1, element: 4)
    static let record = InsertionRecord(field: field, range: 4..<9, text: "hello")

    private func target(focused: FieldIdentity? = field, secure: Bool = false) -> EditTarget {
        EditTarget(record: Self.record, focused: focused, isSecure: secure)
    }

    private func refusal(_ field: FakeSelectionField, _ target: EditTarget) -> TextInsertionError? {
        #expect(throws: TextInsertionError.self) {
            try SelectionWriter(field: field).edit(target, to: "")
        }
    }

    @Test("a delete leaves the text either side byte-identical")
    func deletesTheSpan() throws {
        let field = FakeSelectionField("Hi, hello", caret: 9)
        try SelectionWriter(field: field).edit(target(), to: "")
        #expect(field.text == "Hi, ")
        #expect(field.selection == 4..<4)
        #expect(field.textWrites == [""], "one write, so one undo step")
    }

    @Test("a replacement lands in the span and leaves the caret after it")
    func replacesTheSpan() throws {
        let field = FakeSelectionField("Hi, hello!", caret: 9)
        try SelectionWriter(field: field).edit(target(), to: "world")
        #expect(field.text == "Hi, world!")
        #expect(field.selection == 9..<9)
    }

    @Test("refuses when the span was edited since")
    func refusesAnEditedSpan() {
        let field = FakeSelectionField("Hi, jello", caret: 9)
        #expect(isRejection(refusal(field, target())))
        #expect(field.text == "Hi, jello")
        #expect(field.textWrites.isEmpty)
    }

    @Test("refuses when the selection moved since")
    func refusesAMovedSelection() {
        let field = FakeSelectionField("Hi, hello", caret: 2)
        #expect(isRejection(refusal(field, target())))
        #expect(field.textWrites.isEmpty)
    }

    @Test("refuses when another field is in front")
    func refusesAnotherField() {
        let field = FakeSelectionField("Hi, hello", caret: 9)
        #expect(isRejection(refusal(field, target(focused: Self.other))))
        #expect(isRejection(refusal(field, target(focused: nil))))
        #expect(field.textWrites.isEmpty)
    }

    @Test("refuses a secure field")
    func refusesASecureField() {
        let field = FakeSelectionField("Hi, hello", caret: 9)
        #expect(isRejection(refusal(field, target(secure: true))))
        #expect(field.textWrites.isEmpty)
    }

    @Test("refuses a field that will not report or select ranges")
    func refusesWithoutRanges() {
        let silent = FakeSelectionField("Hi, hello", caret: 9) { $0.reportsValue = false }
        #expect(isRejection(refusal(silent, target())))
        let fixed = FakeSelectionField("Hi, hello", caret: 9) { $0.refusesSelection = true }
        #expect(isRejection(refusal(fixed, target())))
        #expect(fixed.textWrites.isEmpty)
    }

    @Test("restores the caret when the field refuses the text")
    func restoresTheCaretOnRefusal() {
        let field = FakeSelectionField("Hi, hello", caret: 9) { $0.refusesText = true }
        #expect(isRejection(refusal(field, target())))
        #expect(field.selection == 9..<9)
    }

    @Test("does not claim an edit that changed nothing")
    func unchangedIsUnconfirmed() {
        let field = FakeSelectionField("Hi, hello", caret: 9) { $0.ignoresText = true }
        #expect(refusal(field, target()) == .insertionUnconfirmed)
    }
}

private func isRejection(_ error: TextInsertionError?) -> Bool {
    if case .insertionRejected = error { true } else { false }
}
