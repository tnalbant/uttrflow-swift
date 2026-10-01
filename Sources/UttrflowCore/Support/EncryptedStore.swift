// Encrypts complete local-store files and migrates decoded legacy JSON in place.

public import CryptoKit
public import Foundation
import os
import Security

/// A source of the installation key used to seal local store files.
public protocol StoreKeyProviding: Sendable {
    /// Loads or creates the key only when the caller has established that the file is new or legacy.
    func key(createIfMissing: Bool) throws -> SymmetricKey
}

/// The shared versioned envelope for encrypted local JSON files.
public struct EncryptedStore: Sendable {
    private static let log = Logger(subsystem: LocalStore.productionIdentifier, category: "store-encryption")
    private static let magic = Data("UTTFLOWE".utf8)
    private static let version: UInt8 = 1
    private static let nonceLength = 12
    private static let tagLength = 16
    private let keys: any StoreKeyProviding

    /// Uses the production Keychain provider unless a test supplies an isolated provider.
    public init(keys: (any StoreKeyProviding)? = nil) {
        self.keys = keys ?? KeychainStoreKeyProvider()
    }

    /// Reads, authenticates and decodes one JSON file, migrating valid legacy JSON atomically.
    public func read<Value: Decodable & Encodable & Sendable>(
        _ type: Value.Type, from url: URL, now: Date = Date()
    ) -> StoredList<Value> {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .missing
        } catch {
            return .unreadable(setAside: LocalStore.setAside(url, now: now))
        }
        let isEnvelope = data.starts(with: Self.magic)
        do {
            let payload: Data
            if isEnvelope {
                let key: SymmetricKey
                do {
                    key = try keys.key(createIfMissing: false)
                } catch StoreKeyError.unavailable(let status) where status == Int32(errSecItemNotFound) {
                    Self.log.error(
                        "Encrypted store key is missing for \(url.lastPathComponent, privacy: .public)")
                    return .unreadable(setAside: LocalStore.setAside(url, now: now))
                } catch {
                    Self.log.error(
                        "Encrypted store key is unavailable for \(url.lastPathComponent, privacy: .public)")
                    return .unreadable(setAside: nil)
                }
                payload = try Self.open(data, key: key, name: url.lastPathComponent)
            } else {
                payload = data
            }
            let value: Value
            do {
                value = try JSONDecoder().decode(type, from: payload)
            } catch {
                if !isEnvelope { return .unreadable(setAside: nil) }
                throw error
            }
            if !isEnvelope {
                do {
                    let key = try keys.key(createIfMissing: true)
                    try PrivateFile.write(Self.seal(payload, key: key, name: url.lastPathComponent), to: url)
                } catch {
                    Self.log.error(
                        "Legacy store migration failed for \(url.lastPathComponent, privacy: .public)")
                    return .unreadable(setAside: nil)
                }
            }
            return .read(value)
        } catch {
            Self.log.error(
                "Encrypted store could not be authenticated or decoded for \(url.lastPathComponent, privacy: .public)"
            )
            return .unreadable(setAside: LocalStore.setAside(url, now: now))
        }
    }

    /// Writes JSON only after sealing it with filename-bound authenticated data.
    public func write<Value: Encodable & Sendable>(_ value: Value, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
        var key: SymmetricKey
        do {
            let existing = try Data(contentsOf: url)
            guard existing.starts(with: Self.magic) else { throw StoreKeyError.legacyFileNeedsMigration }
            key = try keys.key(createIfMissing: false)
            _ = try Self.open(existing, key: key, name: url.lastPathComponent)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            key = try keys.key(createIfMissing: true)
        }
        try PrivateFile.write(Self.seal(data, key: key, name: url.lastPathComponent), to: url)
    }

    /// Encrypts already encoded JSON while keeping file I/O with the caller.
    public func seal(_ payload: Data, for logicalName: String) throws -> Data {
        let key = try keys.key(createIfMissing: true)
        return try Self.seal(payload, key: key, name: logicalName)
    }

    /// Opens a sealed binary asset, refusing when the installation key is missing or the file was changed.
    public func open(_ envelope: Data, for logicalName: String) throws -> Data {
        let key = try keys.key(createIfMissing: false)
        return try Self.open(envelope, key: key, name: logicalName)
    }

    /// Whether bytes carry this store's versioned envelope header.
    public static func isSealed(_ payload: Data) -> Bool { payload.starts(with: magic) }

    private static func seal(_ payload: Data, key: SymmetricKey, name: String) throws -> Data {
        let box = try AES.GCM.seal(payload, using: key, authenticating: Data(name.utf8))
        guard let combined = box.combined else { throw CocoaError(.fileWriteUnknown) }
        var envelope = magic
        envelope.append(version)
        envelope.append(combined)
        return envelope
    }

    private static func open(_ envelope: Data, key: SymmetricKey, name: String) throws -> Data {
        let headerLength = magic.count + 1
        guard envelope.count >= headerLength + nonceLength + tagLength,
            envelope.prefix(magic.count) == magic,
            envelope[magic.count] == version
        else { throw CocoaError(.fileReadCorruptFile) }
        let combined = envelope.dropFirst(headerLength)
        let box = try AES.GCM.SealedBox(combined: Data(combined))
        return try AES.GCM.open(box, using: key, authenticating: Data(name.utf8))
    }
}

/// Keeps one non-synchronizable, device-only key in the stable production Keychain service.
public struct KeychainStoreKeyProvider: StoreKeyProviding {
    /// The versioned service shared across product upgrades.
    public static let service = "com.uttrflow.local-store.encryption.v1"

    /// Reads the current user's key and creates it only for a new or successfully decoded legacy store.
    public func key(createIfMissing: Bool) throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: NSUserName(),
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true,
        ]
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound, createIfMissing else {
            throw StoreKeyError.unavailable(Int32(status))
        }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        var insertion = query
        insertion[kSecValueData as String] = data
        insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(insertion as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw StoreKeyError.unavailable(Int32(addStatus)) }
        return key
    }
}

/// A Keychain refusal is retained so callers cannot mistake it for an empty store.
public enum StoreKeyError: Error, Sendable {
    /// The Security framework status that prevented the key read or write.
    case unavailable(Int32)
    /// A caller must decode a plaintext file through `read` before replacing it.
    case legacyFileNeedsMigration
}
