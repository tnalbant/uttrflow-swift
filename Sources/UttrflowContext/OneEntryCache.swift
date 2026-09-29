import Synchronization

/// Keeps one value and drops it whenever a lookup names another key.
final class OneEntryCache<Key: Equatable & Sendable, Value: Sendable>: Sendable {
    private struct Entry: Sendable {
        let key: Key
        let value: Value
    }

    private let entry = Mutex<Entry?>(nil)

    /// Returns the value for `key`, evicting an answer for a different identity.
    func value(for key: Key) -> Value? {
        entry.withLock { entry in
            guard let current = entry else { return nil }
            guard current.key == key else {
                entry = nil
                return nil
            }
            return current.value
        }
    }

    /// Replaces the one retained value.
    func insert(_ value: Value, for key: Key) {
        entry.withLock { $0 = Entry(key: key, value: value) }
    }

    /// Releases the retained value when focus may have moved.
    func clear() { entry.withLock { $0 = nil } }
}
