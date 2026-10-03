/// Decodes one saved setting without discarding the readable values beside it in an array or dictionary.
package struct ReadableSetting<Value: Decodable>: Decodable {
    package let value: Value?

    package init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}

extension KeyedDecodingContainer {
    /// Reads an array's readable elements; a missing array, or one whose every element is unreadable, is `fallback`.
    package func readableElements<Element: Decodable>(
        of _: Element.Type, forKey key: Key, fallback: [Element]
    ) -> [Element] {
        guard let saved = try? decode([ReadableSetting<Element>].self, forKey: key) else { return fallback }
        let readable = saved.compactMap(\.value)
        return readable.isEmpty && !saved.isEmpty ? fallback : readable
    }
}
