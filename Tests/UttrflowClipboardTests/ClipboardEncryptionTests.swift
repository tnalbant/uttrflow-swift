// Clipboard text indexes and picture files use the shared authenticated local-store envelope.

import CryptoKit
import Foundation
import Testing
import UttrflowCore

@testable import UttrflowClipboard

@Suite("Encrypted clipboard files")
struct ClipboardEncryptionTests {
    private struct Keys: StoreKeyProviding {
        let value: SymmetricKey
        func key(createIfMissing: Bool) throws -> SymmetricKey { value }
    }

    private func encryptedStore() -> EncryptedStore {
        EncryptedStore(keys: Keys(value: SymmetricKey(size: .bits256)))
    }

    @Test("clipboard indexes and picture bytes are sealed and survive a relaunch")
    func filesAreSealed() async throws {
        let folder = try TemporaryFolder()
        let crypto = encryptedStore()
        let file = folder.url.appending(path: "clipboard.json")
        let store = ClipboardStore(file: file, encryptedStore: crypto)
        let original = Data(repeating: 0x89, count: 4096)
        let noticed = NoticedClip(
            clip: Clip(text: "private clipboard phrase", kind: .image, copiedAt: Date()),
            picture: (original, 32, 32))
        _ = try await store.record(noticed, keeping: folder.retention)

        let index = try Data(contentsOf: file)
        #expect(EncryptedStore.isSealed(index))
        #expect(!String(decoding: index, as: UTF8.self).contains("private clipboard phrase"))
        let clip = try #require(await store.clips(keeping: folder.retention).first)
        let image = try #require(clip.image)
        let pictureURL = await store.imagesFolder.appending(path: image.file)
        let picture = try Data(contentsOf: pictureURL)
        #expect(EncryptedStore.isSealed(picture))
        #expect(picture != original)

        let reopened = ClipboardStore(file: file, encryptedStore: crypto)
        let restored = try #require(await reopened.clips(keeping: folder.retention).first)
        #expect(restored.text == "private clipboard phrase")
        #expect(await reopened.imageData(for: try #require(restored.image)) == original)
    }

    @Test("legacy clipboard JSON and picture files migrate on first read")
    func legacyFilesMigrate() async throws {
        let folder = try TemporaryFolder()
        let file = folder.url.appending(path: "clipboard.json")
        let name = "legacy.png"
        let original = ClipImageTests.bytes
        let clip = Clip(
            text: "legacy private phrase", kind: .image, copiedAt: Date(),
            image: ClipImage(file: name, width: 1, height: 1, bytes: original.count))
        try JSONEncoder().encode([clip]).write(to: file)
        let images = folder.url.appending(path: "Images", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try original.write(to: images.appending(path: name))

        let store = ClipboardStore(file: file, encryptedStore: encryptedStore())
        let migrated = try #require(await store.clips(keeping: folder.retention).first)
        #expect(EncryptedStore.isSealed(try Data(contentsOf: file)))
        #expect(await store.imageData(for: try #require(migrated.image)) == original)
        #expect(EncryptedStore.isSealed(try Data(contentsOf: images.appending(path: name))))
    }

    @Test("a damaged encrypted picture is preserved in the unreadable set-aside")
    func damagedPictureIsSetAside() async throws {
        let folder = try TemporaryFolder()
        let store = ClipboardStore(
            file: folder.url.appending(path: "clipboard.json"), encryptedStore: encryptedStore())
        let image = try await store.keep(ClipImageTests.bytes, forClip: UUID(), width: 1, height: 1)
        let url = await store.imagesFolder.appending(path: image.file)
        let original = try Data(contentsOf: url)
        var damaged = original
        damaged[damaged.index(before: damaged.endIndex)] ^= 0xff
        try damaged.write(to: url)

        #expect(await store.imageData(for: image) == nil)
        let names = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        let asideName = try #require(names.first { $0.hasPrefix("\(image.file).unreadable-") })
        #expect(try Data(contentsOf: url.deletingLastPathComponent().appending(path: asideName)) == damaged)
    }
}
