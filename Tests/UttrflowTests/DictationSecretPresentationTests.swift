import Foundation
import Testing
import UttrflowHistory
@testable import Uttrflow
@testable import UttrflowUX

@Suite("Dictated secrets share one safe presentation")
struct DictationSecretPresentationTests {
    @Test("History, Home, and Recent use the shared mask and concealment decision")
    func everyDictationSurfaceUsesTheSharedSecretDecision() throws {
        let secret = "password=demo1"
        let now = Date(timeIntervalSince1970: 1_750_000_800)
        let entry = DictationRecord(text: secret, when: now)
        let presentation = DictationTextPresentation(secret)
        let history = HistoryPresenter.page(
            for: HistorySnapshot(entries: [entry], now: now),
            locale: Locale(identifier: "en_GB"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let activity = HomeDashboard.activity(
            for: entry, calendar: calendar, locale: Locale(identifier: "en_GB"))
        let home = HomePresenter.page(
            for: HomeSnapshot(entries: [entry], shortcut: "⌥Space", now: now),
            calendar: calendar, locale: Locale(identifier: "en_GB"))
        let preview = try #require(RecentDictations(showing: [entry]).previews.first)
        let menu = MenuBarPresenter.present(
            MenuBarState(recents: [
                MenuBarRecent(
                    id: entry.id,
                    title: preview.title, fullText: preview.isSecret ? preview.title : secret,
                    isSecret: preview.isSecret)
            ]))

        #expect(presentation.isSecret)
        #expect(presentation.displayText == String(repeating: "•", count: 12))
        #expect(history.days.flatMap(\.rows).first?.text == presentation.displayText)
        #expect(activity.text == presentation.displayText)
        #expect(home.recent.first?.text == presentation.displayText)
        #expect(preview.title == presentation.displayText)
        #expect(preview.isSecret)
        #expect(menu.lastDictation?.tooltip == nil)
        #expect(menu.lastDictation?.insert.intent == .insertRecent(id: entry.id))
        #expect(menu.lastDictation?.copy.intent == .copyRecent(id: entry.id))
    }
}
