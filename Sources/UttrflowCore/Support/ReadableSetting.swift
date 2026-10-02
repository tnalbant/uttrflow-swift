/// Decodes one saved setting without discarding the readable values beside it in an array or dictionary.
package struct ReadableSetting<Value: Decodable>: Decodable {
    package let value: Value?

    package init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}
