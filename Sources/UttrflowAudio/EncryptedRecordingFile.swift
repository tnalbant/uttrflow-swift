// The crash-recoverable, authenticated chunk format used for waiting dictation recordings.

import Foundation
import UttrflowCore

enum EncryptedRecordingFile {
    static let magic = Data("UTTRWAV1".utf8)
    static let headerSize = magic.count
    static let chunkHeaderSize = 8
    static let bytesPerFrame = 2
    static let maximumChunkFrames = 16_000
    private static let maximumEnvelopeSize = maximumChunkFrames * bytesPerFrame + 64

    static func isEncrypted(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: headerSize)) == magic
    }

    static func chunkName(for url: URL, index: Int, frames: Int) -> String {
        "\(url.lastPathComponent)#chunk-\(index)#frames-\(frames)"
    }

    static func record(
        _ pcm: Data, frames: Int, index: Int, url: URL, encryptedStore: EncryptedStore
    ) throws -> Data {
        guard frames > 0, frames <= maximumChunkFrames, pcm.count == frames * bytesPerFrame else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let envelope = try encryptedStore.seal(
            pcm, for: chunkName(for: url, index: index, frames: frames))
        var record = Data()
        record.appendLittleEndian(UInt32(frames))
        record.appendLittleEndian(UInt32(envelope.count))
        record.append(envelope)
        return record
    }

    static func encode(
        _ audio: AudioSamples, to url: URL, encryptedStore: EncryptedStore
    ) throws {
        let creationDate = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
        var file = magic
        var index = 0
        for start in stride(from: 0, to: audio.samples.count, by: maximumChunkFrames) {
            let end = min(start + maximumChunkFrames, audio.samples.count)
            let pcm = WAVEncoder.pcm(Array(audio.samples[start..<end]))
            file.append(
                try record(
                    pcm, frames: end - start, index: index, url: url, encryptedStore: encryptedStore))
            index += 1
        }
        try PrivateFile.write(file, to: url)
        if let creationDate {
            try? FileManager.default.setAttributes([.creationDate: creationDate], ofItemAtPath: url.path)
        }
    }

    static func read(from url: URL, encryptedStore: EncryptedStore) throws -> AudioSamples {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard try readExactly(headerSize, from: handle) == magic else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var index = 0
        var samples: [Float] = []
        while true {
            // A crash during the final record leaves only a prefix; complete earlier chunks remain usable.
            let chunkHeader = try readExactly(chunkHeaderSize, from: handle)
            guard !chunkHeader.isEmpty else { break }
            guard chunkHeader.count == chunkHeaderSize else { break }
            let frames = Int(chunkHeader.readLittleEndianUInt32(at: 0))
            let length = Int(chunkHeader.readLittleEndianUInt32(at: 4))
            guard frames > 0, frames <= maximumChunkFrames,
                length >= 37, length <= maximumEnvelopeSize
            else { throw CocoaError(.fileReadCorruptFile) }
            let envelope = try readExactly(length, from: handle)
            guard envelope.count == length else { break }
            let pcm = try encryptedStore.open(
                envelope, for: chunkName(for: url, index: index, frames: frames))
            guard pcm.count == frames * bytesPerFrame else {
                throw CocoaError(.fileReadCorruptFile)
            }
            for sampleIndex in stride(from: 0, to: pcm.count, by: bytesPerFrame) {
                let bits = UInt16(pcm[sampleIndex]) | UInt16(pcm[sampleIndex + 1]) << 8
                samples.append(Float(Int16(bitPattern: bits)) / Float(Int16.max))
            }
            index += 1
        }
        return .canonical(samples)
    }

    private static func readExactly(_ count: Int, from handle: FileHandle) throws -> Data {
        var data = Data()
        while data.count < count {
            guard let next = try handle.read(upToCount: count - data.count), !next.isEmpty else { break }
            data.append(next)
        }
        return data
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    func readLittleEndianUInt32(at offset: Int) -> UInt32 {
        UInt32(self[offset]) | UInt32(self[offset + 1]) << 8 | UInt32(self[offset + 2]) << 16
            | UInt32(self[offset + 3]) << 24
    }
}
