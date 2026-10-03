import Testing

@testable import Uttrflow

@Suite("Personal data export disclosure")
struct PersonalDataExportTests {
    @Test("warns that exported JSON is not encrypted and offers secret-snippet exclusion")
    func disclosesPlaintextAndExclusionChoice() {
        #expect(PersonalDataExport.disclosureMessage.contains("not encrypted"))
        #expect(PersonalDataExport.disclosureMessage.contains("exclude snippets"))
    }

    @Test("excludes snippets containing recognized credentials when chosen")
    func excludesRecognizedCredentialSnippets() {
        let archive = PersonalDataExport.archive(
            dictionary: [],
            snippets: [
                .init(trigger: "safe phrase", expansion: "ordinary text", created: .distantPast),
                .init(trigger: "database login", expansion: "password=hunter2", created: .distantPast),
            ],
            choice: .excludeSecretSnippets)

        #expect(archive.snippets.map(\.trigger) == ["safe phrase"])
    }

    @Test("keeps every snippet when the user chooses to include them")
    func includesAllSnippetsWhenChosen() {
        let snippets = [
            .init(trigger: "database login", expansion: "password=hunter2", created: .distantPast)
        ]

        let archive = PersonalDataExport.archive(
            dictionary: [], snippets: snippets, choice: .includeAllSnippets)

        #expect(archive.snippets == snippets)
    }
}
