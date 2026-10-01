// Tests for authenticated local-store files and legacy migration.

import CryptoKit
import Foundation
import Security
import Testing

@testable import UttrflowCore

@Suite("Encrypted local stores")
struct EncryptedStoreTests {
    private struct Keys: StoreKeyProviding {
        let value: SymmetricKey
        func key(createIfMissing: Bool) throws -> SymmetricKey { value }
    }

    private struct MissingKey: StoreKeyProviding {
        func key(createIfMissing: Bool) throws -> SymmetricKey {
            throw StoreKeyError.unavailable(Int32(errSecItemNotFound))
        }
    }

    private struct LockedKey: StoreKeyProviding {
        func key(createIfMissing: Bool) throws -> SymmetricKey {
            throw StoreKeyError.unavailable(Int32(errSecInteractionNotAllowed))
        }
    }

    private func folder() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "uttrflow-encrypted-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("writes a filename-bound envelope and reads it back")
    func roundTrip() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "history.v1.json")
        let store = EncryptedStore(keys: Keys(value: SymmetricKey(size: .bits256)))
        try store.write(["private"], to: file)

        #expect(try Data(contentsOf: file).starts(with: Data("UTTFLOWE".utf8)))
        #expect(store.read([String].self, from: file).value == ["private"])
    }

    @Test("rejects a different key and leaves the source bytes set aside")
    func wrongKey() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "history.v1.json")
        let writer = EncryptedStore(keys: Keys(value: SymmetricKey(size: .bits256)))
        try writer.write(["private"], to: file)
        let reader = EncryptedStore(keys: Keys(value: SymmetricKey(size: .bits256)))
        let stored = reader.read([String].self, from: file)

        #expect(stored.isUnreadable)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(LocalStore.hasSetAside(file))
    }

    @Test("migrates valid legacy JSON and preserves its decoded value")
    func migratesLegacy() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "history.v1.json")
        try Data("[\"private\"]".utf8).write(to: file)
        let store = EncryptedStore(keys: Keys(value: SymmetricKey(size: .bits256)))

        #expect(store.read([String].self, from: file).value == ["private"])
        #expect(try Data(contentsOf: file).starts(with: Data("UTTFLOWE".utf8)))
    }

    @Test("leaves malformed legacy JSON in place without asking for a key")
    func malformedLegacyStaysInPlace() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "history.v1.json")
        let source = Data("{ malformed".utf8)
        try source.write(to: file)

        let stored = EncryptedStore(keys: MissingKey()).read([String].self, from: file)

        #expect(stored.isUnreadable)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(try Data(contentsOf: file) == source)
        #expect(!LocalStore.hasSetAside(file))
    }

    @Test("rejects a renamed store because the logical filename is authenticated")
    func wrongFilename() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "history.v1.json")
        let renamed = directory.appending(path: "snippets.v1.json")
        let store = EncryptedStore(keys: Keys(value: SymmetricKey(size: .bits256)))
        try store.write(["private"], to: file)
        try FileManager.default.moveItem(at: file, to: renamed)

        #expect(store.read([String].self, from: renamed).isUnreadable)
        #expect(LocalStore.hasSetAside(renamed))
    }

    @Test("does not quarantine an encrypted file while its keychain is temporarily locked")
    func lockedKeyLeavesFileInPlace() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "history.v1.json")
        let writer = EncryptedStore(keys: Keys(value: SymmetricKey(size: .bits256)))
        try writer.write(["private"], to: file)
        let source = try Data(contentsOf: file)
        let reader = EncryptedStore(keys: LockedKey())

        let stored = reader.read([String].self, from: file)

        #expect(stored.isUnreadable)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(try Data(contentsOf: file) == source)
        #expect(!LocalStore.hasSetAside(file))
    }

    @Test("quarantines an encrypted file when its key is definitely missing")
    func missingKeyQuarantines() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "history.v1.json")
        try EncryptedStore(keys: Keys(value: SymmetricKey(size: .bits256))).write(["private"], to: file)

        let stored = EncryptedStore(keys: MissingKey()).read([String].self, from: file)

        #expect(stored.isUnreadable)
        #expect(LocalStore.hasSetAside(file))
    }

    @Test("does not replace an encrypted file when its key is missing")
    func missingKeyCannotReplaceEncryptedFile() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "history.v1.json")
        try EncryptedStore(keys: Keys(value: SymmetricKey(size: .bits256))).write(["private"], to: file)
        let source = try Data(contentsOf: file)

        do {
            try EncryptedStore(keys: MissingKey()).write(["replacement"], to: file)
            Issue.record("Expected a missing key to prevent replacing the encrypted file")
        } catch StoreKeyError.unavailable(let status) {
            #expect(status == Int32(errSecItemNotFound))
        }

        #expect(try Data(contentsOf: file) == source)
    }

    @Test("rejects unsupported, truncated and modified envelopes")
    func malformedEnvelopes() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "history.v1.json")
        let store = EncryptedStore(keys: Keys(value: SymmetricKey(size: .bits256)))
        try store.write(["private"], to: file)
        let valid = try Data(contentsOf: file)
        for (index, invalid) in [
            Data(valid.dropLast(4)),
            Data(valid.enumerated().map { $0.offset == valid.count - 1 ? $0.element ^ 0x01 : $0.element }),
            Data(valid.enumerated().map { $0.offset == 8 ? 0x02 : $0.element }),
        ].enumerated() {
            try invalid.write(to: file)
            #expect(store.read([String].self, from: file).isUnreadable, "invalid envelope \(index)")
            try valid.write(to: file)
        }
    }
}
