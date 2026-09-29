import Testing

@testable import UttrflowCore

@Suite("ListeningLanguages")
struct ListeningLanguagesTests {
    @Test(
        "reads how each piece gets its language off the languages the user speaks",
        arguments: [
            ([LanguageCode.english], ListeningLanguages.eachPiece), ([], .eachPiece),
            ([.hindi], .only(.hindi)), ([.english, .hindi], .eachPiece), ([.hindi, .english], .eachPiece),
            ([.hindi, LanguageCode("fr") ?? .english], .only(.hindi)),
        ])
    func fromProfile(languages: [LanguageCode], listening: ListeningLanguages) {
        #expect(ListeningLanguages(profile: UserProfile(preferredLanguages: languages)) == listening)
    }

    @Test("the default profile detects every piece")
    func defaultProfileDetectsEveryPiece() {
        #expect(ListeningLanguages(profile: .default) == .eachPiece)
    }

    @Test("hints a later piece with the pinned language, nothing, or the first piece's language")
    func hints() {
        #expect(ListeningLanguages.only(.hindi).hint(afterFirstPiece: nil) == .hindi)
        #expect(ListeningLanguages.only(.hindi).hint(afterFirstPiece: .english) == .hindi)
        #expect(ListeningLanguages.eachPiece.hint(afterFirstPiece: .english) == nil)
        #expect(ListeningLanguages.firstPiece.hint(afterFirstPiece: .english) == .english)
        #expect(ListeningLanguages.firstPiece.hint(afterFirstPiece: nil) == nil)
    }
}
