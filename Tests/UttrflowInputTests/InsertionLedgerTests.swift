import Testing

@testable import UttrflowCore
@testable import UttrflowInput

@Suite("InsertionLedger")
struct InsertionLedgerTests {
    private static let field = FieldIdentity(processIdentifier: 7, windowNumber: 3, element: 11)
    private static let other = FieldIdentity(processIdentifier: 7, windowNumber: 3, element: 12)

    /// Focus that reports one placed field, as a reader that can tell fields apart does.
    private struct PlacedFocus: AccessibilityFocus {
        let place: FieldPlace?
        var secure = false
        func focusedTextField() -> (any FocusedTextField)? { nil }
        func hasFocusedElement() -> Bool { true }
        func isSelfFrontmost() -> Bool { false }
        func focusedFieldIsSecure() -> Bool { secure }
        func focusedFieldPlace() -> FieldPlace? { place }
    }

    private func coordinator(
        _ method: TextInsertionMethod, arrival: InsertionArrival = .confirmed,
        error: TextInsertionError? = nil, place: FieldPlace?, secure: Bool = false, ledger: InsertionLedger
    ) -> TextInsertionCoordinator {
        TextInsertionCoordinator(
            strategies: [StubInsertionEngine(method: method, error: error, arrival: arrival)],
            focus: PlacedFocus(place: place, secure: secure), ledger: ledger)
    }

    @Test("a confirmed Accessibility write records the span the words now occupy")
    func recordsConfirmedWrite() async throws {
        let ledger = InsertionLedger()
        let place = FieldPlace(field: Self.field, caret: 10)
        try await coordinator(.accessibility, place: place, ledger: ledger).insert("héllo")

        let records = ledger.records(in: Self.field)
        #expect(records == [InsertionRecord(field: Self.field, range: 5..<10, text: "héllo")])
    }

    @Test(
        "a write that was not confirmed leaves nothing to act on",
        arguments: [
            (TextInsertionMethod.accessibility, InsertionArrival.unconfirmed),
            (.accessibility, .notReported),
            (.clipboard, .confirmed),
            (.pasteboard, .confirmed),
            (.typed, .confirmed),
        ])
    func unconfirmedWriteEmpties(method: TextInsertionMethod, arrival: InsertionArrival) async throws {
        let ledger = InsertionLedger()
        let place = FieldPlace(field: Self.field, caret: 5)
        try await coordinator(.accessibility, place: place, ledger: ledger).insert("hello")
        try await coordinator(method, arrival: arrival, place: place, ledger: ledger).insert("world")

        #expect(ledger.records(in: Self.field).isEmpty)
    }

    @Test("a write into a secure field is never remembered")
    func secureFieldEmpties() async throws {
        let ledger = InsertionLedger()
        let place = FieldPlace(field: Self.field, caret: 5)
        try await coordinator(.accessibility, place: place, secure: true, ledger: ledger).insert("hello")

        #expect(ledger.records(in: Self.field).isEmpty)
    }

    @Test("a failed write empties the ledger")
    func failureEmpties() async throws {
        let ledger = InsertionLedger()
        let place = FieldPlace(field: Self.field, caret: 5)
        try await coordinator(.accessibility, place: place, ledger: ledger).insert("hello")
        await #expect(throws: TextInsertionError.self) {
            try await coordinator(.accessibility, error: .accessibilityDenied, place: place, ledger: ledger)
                .insert("world")
        }

        #expect(ledger.records(in: Self.field).isEmpty)
    }

    @Test("asking from another field, window or app empties the ledger")
    func fieldChangeEmpties() async throws {
        let ledger = InsertionLedger()
        try await coordinator(.accessibility, place: FieldPlace(field: Self.field, caret: 5), ledger: ledger)
            .insert("hello")

        #expect(ledger.records(in: Self.other).isEmpty)
        #expect(ledger.records(in: Self.field).isEmpty, "the move away already forgot it")
    }

    @Test("a write into a new field starts a fresh ledger")
    func newFieldRestarts() async throws {
        let ledger = InsertionLedger()
        try await coordinator(.accessibility, place: FieldPlace(field: Self.field, caret: 5), ledger: ledger)
            .insert("hello")
        try await coordinator(.accessibility, place: FieldPlace(field: Self.other, caret: 5), ledger: ledger)
            .insert("world")

        #expect(ledger.records(in: Self.other).map(\.text) == ["world"])
    }

    @Test("a field that cannot be placed leaves nothing to act on")
    func unplacedEmpties() async throws {
        let ledger = InsertionLedger()
        try await coordinator(.accessibility, place: nil, ledger: ledger).insert("hello")

        #expect(ledger.records(in: Self.field).isEmpty)
    }

    @Test("memory is bounded by count and by length")
    func bounded() async throws {
        let ledger = InsertionLedger()
        for index in 1...(InsertionLedger.capacity + 3) {
            try await coordinator(
                .accessibility, place: FieldPlace(field: Self.field, caret: index * 2), ledger: ledger
            ).insert("a\(index % 10)")
        }
        #expect(ledger.records(in: Self.field).count == InsertionLedger.capacity)

        let long = String(repeating: "a", count: InsertionLedger.textLimit + 1)
        let end = FieldPlace(field: Self.field, caret: long.utf16.count)
        try await coordinator(.accessibility, place: end, ledger: ledger).insert(long)
        #expect(ledger.records(in: Self.field).isEmpty)
    }

    @Test("the span is still there until the user types inside it")
    func stillThere() {
        let record = InsertionRecord(field: Self.field, range: 4..<9, text: "hello")

        #expect(record.stillThere(in: "Hi, hello there"))
        #expect(!record.stillThere(in: "Hi, helXlo there"))
        #expect(!record.stillThere(in: "Hi, hell"))
    }
}
