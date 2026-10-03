// The orders the Dictionary and Snippets lists can be read in, and the one rule that applies them.
public import Foundation
public import UttrflowCore
public import UttrflowDictionary

/// An order a page's list can be read in, named by the identifier the sort menu reports back.
public protocol ListSort: RawRepresentable<String>, CaseIterable, Sendable, Equatable {
    /// The item the order applies to.
    associatedtype Item
    /// The order a page opens in, and the one an unknown identifier falls back to.
    static var standard: Self { get }
    /// The menu's words.
    var title: String { get }
    /// Which of two items comes first, before ties are broken by identity.
    func compare(_ lhs: Item, _ rhs: Item, locale: Locale) -> ComparisonResult
}

extension ListSort {
    /// The order an identifier names, or the standard one for an empty or unknown identifier.
    public init(named id: String) { self = Self(rawValue: id) ?? .standard }

    /// The sort menu, with this order selected and named for VoiceOver.
    public var menu: MainScope {
        MainScope(
            title: "Sorted by \(title)",
            options: Self.allCases.map {
                MainScopeOption(id: $0.rawValue, title: $0.title, isSelected: $0 == self)
            })
    }

    /// The items in this order, ties broken by identifier so equal items never swap between redraws.
    public func ordered(_ items: [Item], id: (Item) -> UUID, locale: Locale) -> [Item] {
        items.sorted { lhs, rhs in
            switch compare(lhs, rhs, locale: locale) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: id(lhs).uuidString < id(rhs).uuidString
            }
        }
    }
}

/// How two names are ordered as a person reads a list: ignoring case and accents, digits by value.
func readingOrder(_ lhs: String, _ rhs: String, locale: Locale) -> ComparisonResult {
    lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive, .numeric], locale: locale)
}

/// Larger first, so the most used or most recent item leads.
func descending<Value: Comparable>(_ lhs: Value, _ rhs: Value) -> ComparisonResult {
    lhs == rhs ? .orderedSame : (lhs > rhs ? .orderedAscending : .orderedDescending)
}

/// The orders the Dictionary page offers.
public enum DictionarySort: String, ListSort {
    /// The latest added first.
    case newest
    /// Alphabetical, as a person reads it.
    case name
    /// The most applied first.
    case mostUsed
    /// The most undone first.
    case mostUndone

    /// Newest, so what was just added or learned is on top.
    public static let standard = Self.newest

    /// The menu's words.
    public var title: String {
        switch self {
        case .newest: "Newest"
        case .name: "Name"
        case .mostUsed: "Most used"
        case .mostUndone: "Most undone"
        }
    }

    /// Which of two items comes first.
    public func compare(_ lhs: DictionaryEntry, _ rhs: DictionaryEntry, locale: Locale) -> ComparisonResult {
        switch self {
        case .newest: descending(lhs.firstSeen, rhs.firstSeen)
        case .name: readingOrder(lhs.word, rhs.word, locale: locale)
        case .mostUsed: descending(lhs.timesUsed, rhs.timesUsed)
        case .mostUndone: descending(lhs.timesReverted, rhs.timesReverted)
        }
    }
}

/// The orders the Snippets page offers.
public enum SnippetSort: String, ListSort {
    /// The latest added first.
    case newest
    /// Alphabetical, as a person reads it.
    case name
    /// The most applied first.
    case mostUsed
    /// The most recently used first.
    case lastUsed

    /// Newest, so what was just added or learned is on top.
    public static let standard = Self.newest

    /// The menu's words.
    public var title: String {
        switch self {
        case .newest: "Newest"
        case .name: "Name"
        case .mostUsed: "Most used"
        case .lastUsed: "Last used"
        }
    }

    /// Which of two items comes first.
    public func compare(_ lhs: Snippet, _ rhs: Snippet, locale: Locale) -> ComparisonResult {
        switch self {
        case .newest: descending(lhs.created, rhs.created)
        case .name: readingOrder(lhs.trigger, rhs.trigger, locale: locale)
        case .mostUsed: descending(lhs.timesUsed, rhs.timesUsed)
        case .lastUsed: Self.recency(lhs.lastUsed, rhs.lastUsed)
        }
    }

    /// Most recently used first; a snippet never used is its own case and comes after every used one.
    static func recency(_ lhs: Date?, _ rhs: Date?) -> ComparisonResult {
        switch (lhs, rhs) {
        case (nil, nil): .orderedSame
        case (nil, _): .orderedDescending
        case (_, nil): .orderedAscending
        case (let lhs?, let rhs?): descending(lhs, rhs)
        }
    }
}
