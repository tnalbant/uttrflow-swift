// Tests what the panel shows in the moment between the window appearing and the store answering.
import Foundation
import Testing
import UttrflowClipboard

@testable import UttrflowUX

/// The window is shown before the list is read, so the panel has to say nothing about a list it lacks.
@Suite("The panel between showing and its list arriving")
struct PanelOpeningTests {
    @Test("a panel shown before the store answers takes typing and lists nothing")
    func opensEmptyAndTypeable() {
        let opening = PanelSnapshot.opening(now: PanelFixture.now)

        #expect(opening.isAwaitingList)
        let shown = PanelPresenter.present(opening)
        #expect(shown.rows.isEmpty)
        #expect(shown.query.isEmpty)
    }

    /// "Nothing copied yet" over a full clipboard is the specific-and-wrong error. See `Docs/panel.md`.
    @Test("and says nothing about being empty, because an unread list is unknown, not nothing")
    func saysNothingYet() {
        let shown = PanelPresenter.present(PanelSnapshot.opening(now: PanelFixture.now))

        #expect(shown.emptyState == nil)
        #expect(shown.emptyAction == nil)
    }

    /// A search typed into the gap must not be answered by a list that has not been read.
    @Test("nor offers to keep a search it has not looked for yet")
    func offersNothingForAQueryYet() {
        var opening = PanelSnapshot.opening(now: PanelFixture.now)
        opening.query = "first"

        #expect(PanelPresenter.present(opening).emptyAction == nil)
    }

    @Test("the list arriving says what it means, and an empty clipboard then says so")
    func installedEmptyListSaysSo() {
        var opening = PanelSnapshot.opening(now: PanelFixture.now)
        opening.install([], missingImages: [], formattableLanguages: [], now: PanelFixture.now)

        #expect(!opening.isAwaitingList)
        #expect(PanelPresenter.present(opening).emptyState?.title == "Nothing copied yet")
    }

    @Test("what was typed while the list was on its way filters the list that arrives")
    func typingSurvivesTheList() {
        var opening = PanelSnapshot.opening(now: PanelFixture.now, locale: PanelFixture.locale)
        opening.query = "second"
        opening.install(
            PanelFixture.clips, missingImages: [], formattableLanguages: [], now: PanelFixture.now)

        #expect(opening.query == "second")
        #expect(PanelPresenter.present(opening).rows.map(\.summary) == ["The second thing"])
    }

    /// A3, A7 — the place cannot be restored before the list it has to exist in is here.
    @Test("the place the user left is restored by the list arriving, not by the window appearing")
    func resumeWaitsForTheList() {
        let resume = PanelResume(
            category: "Work", selection: nil, sheet: nil,
            closedAt: PanelFixture.now.addingTimeInterval(-3))
        var opening = PanelSnapshot.opening(now: PanelFixture.now, resuming: resume)
        #expect(opening.category == nil)

        opening.install(
            [PanelFixture.clip("filed", minutesAgo: 1, category: "Work")], missingImages: [],
            formattableLanguages: [], now: PanelFixture.now)

        #expect(opening.category == "Work")
    }

    /// Restoring a collection over a search would empty the list the user is watching fill.
    @Test("but a panel already typed into keeps what the user is doing")
    func typingOutranksTheResume() {
        let resume = PanelResume(
            category: "Work", selection: nil, sheet: nil,
            closedAt: PanelFixture.now.addingTimeInterval(-3))
        var opening = PanelSnapshot.opening(now: PanelFixture.now, resuming: resume)
        opening.query = "filed"
        opening.install(
            [PanelFixture.clip("filed", minutesAgo: 1, category: "Work")], missingImages: [],
            formattableLanguages: [], now: PanelFixture.now)

        #expect(opening.category == nil)
    }

    /// The caught-up clip arrives by the refresh path, into a panel that is already on screen.
    @Test("a copy arriving later is added without restoring the resume a second time")
    func aLaterCopyDoesNotRestoreAgain() {
        let filed = PanelFixture.clip("filed", minutesAgo: 2, category: "Work")
        let resume = PanelResume(
            category: "Work", selection: nil, sheet: nil,
            closedAt: PanelFixture.now.addingTimeInterval(-3))
        var opening = PanelSnapshot.opening(
            now: PanelFixture.now, locale: PanelFixture.locale, resuming: resume)
        opening.install([filed], missingImages: [], formattableLanguages: [], now: PanelFixture.now)
        #expect(opening.category == "Work")
        // The user leaves the collection, as the All chip does.
        opening.category = nil

        let copied = PanelFixture.clip("just copied", minutesAgo: 0)
        opening.install(
            [copied, filed], missingImages: [], formattableLanguages: [], now: PanelFixture.now)

        #expect(opening.category == nil)
        #expect(PanelPresenter.present(opening).rows.map(\.summary) == ["just copied"])
    }
}
