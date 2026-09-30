// Prevents model cleanup from removing weights while a recogniser is using them.
import Darwin
import Foundation

final class ModelDirectoryUseLease: @unchecked Sendable {
    private let descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        _ = flock(descriptor, LOCK_UN)
        _ = Darwin.close(descriptor)
    }

    static func acquireShared(for modelDirectory: URL) -> Self? {
        acquire(for: modelDirectory, operation: LOCK_SH)
    }

    static func withExclusiveLock<T>(for modelDirectory: URL, _ body: () throws -> T) throws -> T? {
        guard let lease = acquire(for: modelDirectory, operation: LOCK_EX) else { return nil }
        return try withExtendedLifetime(lease, body)
    }

    private static func acquire(for modelDirectory: URL, operation: Int32) -> Self? {
        let lock = modelDirectory.deletingLastPathComponent()
            .appending(path: ".use-\(modelDirectory.lastPathComponent).lock")
        let descriptor = Darwin.open(lock.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, operation | LOCK_NB) == 0 else {
            _ = Darwin.close(descriptor)
            return nil
        }
        return Self(descriptor: descriptor)
    }
}
