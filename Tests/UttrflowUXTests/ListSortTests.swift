// Tests for the sort menus on the Dictionary and Snippets pages, and for dates outside this year.
import Foundation
import UttrflowCore
import UttrflowDictionary
import Testing

@testable import UttrflowUX

@Suite("The order the Dictionary lists its words in")
struct DictionarySortTests {
    static let words = [
        HistoryFixture.word("valkey", daysAgo: 9, used: 4, reverted: 1),
        HistoryFixture.word("Ångström", daysAgo: 1, used: 30, reverted: 0),
        HistoryFixture.word("Kestrel", daysAgo: 5, used: 12, reverted: 2),
    ]

    /// The words in the order the named sort lists them.
    static func listed(_ sort: String, _ words: [DictionaryEntry] = words) -> [String] {
        HistoryFixture.dictionary(entries: words, sort: sort).rows.map(\.word)
    }

    @Test("each order lists the words as its name says")
    func orders() {
        #expect(Self.listed("newest") == ["Ångström", "Kestrel", "valkey"])
        #expect(Self.listed("name") == ["Ångström", "Kestrel", "valkey"])
        #expect(Self.listed("mostUsed") == ["Ångström", "Kestrel", "valkey"])
        #expect(Self.listed("mostUndone") == ["Kestrel", "valkey", "Ångström"])
    }

    @Test("name ignores case and accents rather than putting capitals first")
    func nameReadsAsPeopleRead() {
        let words = [
            HistoryFixture.word("zeta"), HistoryFixture.word("Alpha"), HistoryFixture.word("éclair"),
        ]
        #expect(Self.listed("name", words) == ["Alpha", "éclair", "zeta"])
    }

    @Test("an empty or unknown order is Newest, and the menu says so")
    func standard() {
        #expect(Self.listed("") == Self.listed("newest"))
        #expect(Self.listed("sideways") == Self.listed("newest"))
        let menu = HistoryFixture.dictionary(entries: Self.words).chrome.sort
        #expect(menu?.title == "Sorted by Newest")
        #expect(menu?.options.map(\.title) == ["Newest", "Name", "Most used", "Most undone"])
        #expect(menu?.options.filter(\.isSelected).map(\.id) == ["newest"])
    }

    @Test("the menu names the order in force, which is what VoiceOver reads")
    func spokenTitle() {
        let menu = HistoryFixture.dictionary(entries: Self.words, sort: "mostUndone").chrome.sort
        #expect(menu?.title == "Sorted by Most undone")
    }

    @Test("an empty dictionary has nothing to order and no menu")
    func noMenuWhenEmpty() {
        #expect(HistoryFixture.dictionary().chrome.sort == nil)
    }

    @Test(
        "ties are broken by identity, whatever order the store hands them over in",
        arguments: DictionarySort.allCases)
    func ties(sort: DictionarySort) {
        let twins = (0..<6).map { _ in HistoryFixture.word("Same") }
        let forward = HistoryFixture.dictionary(entries: twins, sort: sort.rawValue).rows.map(\.id)
        let backward = HistoryFixture.dictionary(entries: twins.reversed(), sort: sort.rawValue).rows.map(
            \.id)
        #expect(forward == backward)
        #expect(forward == twins.map(\.id).sorted { $0.uuidString < $1.uuidString })
    }
}

@Suite("The order the Snippets page lists its snippets in")
struct SnippetSortTests {
    static let snippets = [
        HistoryFixture.snippet("sign off", used: 64, lastUsedDaysAgo: 3, createdDaysAgo: 30),
        HistoryFixture.snippet("my address", used: 12, lastUsedDaysAgo: nil, createdDaysAgo: 2),
        HistoryFixture.snippet("Bio", used: 20, lastUsedDaysAgo: 1, createdDaysAgo: 9),
    ]

    /// The triggers in the order the named sort lists them.
    static func listed(_ sort: String) -> [String] {
        HistoryFixture.snippets(Self.snippets, sort: sort).rows.map(\.trigger.text)
    }

    @Test("each order lists the snippets as its name says")
    func orders() {
        #expect(Self.listed("newest") == ["my address", "Bio", "sign off"])
        #expect(Self.listed("name") == ["Bio", "my address", "sign off"])
        #expect(Self.listed("mostUsed") == ["sign off", "Bio", "my address"])
        // Never used is its own case, after every snippet that has been.
        #expect(Self.listed("lastUsed") == ["Bio", "sign off", "my address"])
        #expect(Self.listed("") == Self.listed("newest"))
    }

    @Test("the menu offers the snippet orders, with the chosen one selected")
    func menu() {
        let menu = HistoryFixture.snippets(Self.snippets, sort: "lastUsed").chrome.sort
        #expect(menu?.options.map(\.title) == ["Newest", "Name", "Most used", "Last used"])
        #expect(menu?.title == "Sorted by Last used")
    }

    @Test("ties are broken by identity", arguments: SnippetSort.allCases)
    func ties(sort: SnippetSort) {
        let twins = (0..<6).map { _ in HistoryFixture.snippet("same") }
        let forward = HistoryFixture.snippets(twins, sort: sort.rawValue).rows.map(\.id)
        let backward = HistoryFixture.snippets(twins.reversed(), sort: sort.rawValue).rows.map(\.id)
        #expect(forward == backward)
    }
}

@Suite("Dates outside the current year carry the year")
struct DateYearTests {
    @Test("a word added this year shows day and month, an older one its year too")
    func dictionaryAdded() throws {
        let thisYear = HistoryFixture.word("Recent", daysAgo: 30)
        let lastYear = HistoryFixture.word("Old", daysAgo: 400)
        let rows = HistoryFixture.dictionary(entries: [thisYear, lastYear]).rows
        #expect(rows.map(\.added) == ["16 May", "11 May 2024"])
    }

    @Test("a day long past names its year")
    func day() throws {
        let old = try HistoryFixture.date(year: 2023, month: 8, day: 12)
        #expect(
            MainFormatting.day(
                old, now: HistoryFixture.now, calendar: HistoryFixture.calendar, locale: HistoryFixture.locale
            )
                == "12 Aug 2023")
    }
}
