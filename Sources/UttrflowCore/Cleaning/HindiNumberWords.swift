/// The Hindi number words and the one view every consumer reads both languages through.
extension NumberWords {
    /// Hindi number words in Devanagari and in the romanised spellings people type, by value.
    public static let hindi: [String: Int] = [
        "एक": 1, "ek": 1,
        "दो": 2, "do": 2,
        "तीन": 3, "teen": 3, "tin": 3,
        "चार": 4, "char": 4, "chaar": 4,
        "पांच": 5, "पाँच": 5, "paanch": 5, "panch": 5,
        "छह": 6, "छे": 6, "chhe": 6, "chah": 6,
        "सात": 7, "saat": 7, "sat": 7,
        "आठ": 8, "aath": 8, "ath": 8,
        "नौ": 9, "nau": 9,
        "दस": 10, "das": 10,
        "ग्यारह": 11, "gyarah": 11,
        "बारह": 12, "barah": 12,
        "पंद्रह": 15, "pandrah": 15,
        "बीस": 20, "bees": 20, "bis": 20,
        "तीस": 30, "tees": 30,
        "चालीस": 40, "chalis": 40,
        "पचास": 50, "pachas": 50,
        "सौ": 100, "sau": 100,
        "हज़ार": 1_000, "हजार": 1_000, "hazaar": 1_000, "hazar": 1_000,
    ]

    /// Hindi number words as often an ordinary word, "एक" also "a" and "दो" also "give".
    public static let hindiHomographs: Set<String> = ["एक", "दो", "ek", "do"]

    /// Every English number word by value, the units, teens, tens and scales together.
    public static var english: [String: Int] {
        units.merging(teens) { first, _ in first }.merging(tens) { first, _ in first }
            .merging(scales) { first, _ in first }
    }

    /// Whether a number word is a scale, which multiplies the words before it rather than counting.
    public static func isScale(_ value: Int) -> Bool {
        scales.values.contains(value)
    }
}
