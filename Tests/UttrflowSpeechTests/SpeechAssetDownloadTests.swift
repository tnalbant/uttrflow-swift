import CryptoKit
import Foundation
import Synchronization
import Testing

@testable import UttrflowSpeech

@Suite("Speech asset download progress")
struct SpeechAssetDownloadTests {
    private struct Sandbox: ~Copyable {
        let root: URL

        init() {
            root = FileManager.default.temporaryDirectory
                .appending(path: "uttrflow-speech-download-\(UUID().uuidString)")
        }

        deinit { try? FileManager.default.removeItem(at: root) }
    }

    @Test("reports increasing byte progress before the transport completes")
    func incrementalProgress() async throws {
        let sandbox = Sandbox()
        let root = sandbox.root
        let file = Data([1, 2, 3, 4, 5])
        let digest = SHA256.hash(data: file).map { String(format: "%02x", $0) }.joined()
        let expected = SpeechModelFile(bytes: Int64(file.count), sha256: digest)
        let reports = Mutex<[Int64]>([])
        let finishedTransport = Mutex(false)
        let downloader: SpeechAssetDownloader = { request, partial, _, onProgress in
            onProgress(2)
            onProgress(4)
            #expect(reports.withLock { $0 } == [2, 4])
            #expect(!finishedTransport.withLock { $0 })
            try FileManager.default.createDirectory(
                at: root, withIntermediateDirectories: true)
            guard let url = request.url else { throw URLError(.badURL) }
            let output = try openSpeechAssetOutput(at: partial, statusCode: 200, requestedOffset: 0)
            try output.write(contentsOf: file)
            try output.close()
            let response = try #require(
                HTTPURLResponse(
                    url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:]))
            finishedTransport.withLock { $0 = true }
            return response
        }

        try await fetchPinnedFile(
            repository: "test/model", revision: "pinned", path: "weights.bin",
            destination: root.appending(path: "weights.bin"), expected: expected,
            downloader: downloader
        ) { bytes in
            reports.withLock { $0.append(bytes) }
        }

        #expect(reports.withLock { $0 } == [2, 4, 5])
        #expect(finishedTransport.withLock { $0 })
        #expect(try Data(contentsOf: root.appending(path: "weights.bin")) == file)
    }

    @Test("resumes an interrupted file from its saved byte offset")
    func resumesInterruptedFile() async throws {
        let sandbox = Sandbox()
        let root = sandbox.root
        let file = Data([1, 2, 3, 4, 5, 6])
        let digest = SHA256.hash(data: file).map { String(format: "%02x", $0) }.joined()
        let expected = SpeechModelFile(bytes: Int64(file.count), sha256: digest)
        let requests = Mutex<[Int64]>([])
        let ranges = Mutex<[String?]>([])
        let progress = Mutex<[Int64]>([])
        let downloader: SpeechAssetDownloader = { request, partial, offset, onProgress in
            requests.withLock { $0.append(offset) }
            ranges.withLock { $0.append(request.value(forHTTPHeaderField: "Range")) }
            guard let url = request.url else { throw URLError(.badURL) }
            if offset == 0 {
                try FileManager.default.createDirectory(
                    at: partial.deletingLastPathComponent(), withIntermediateDirectories: true)
                let output = try openSpeechAssetOutput(at: partial, statusCode: 200, requestedOffset: 0)
                try output.write(contentsOf: file.prefix(3))
                try output.close()
                throw URLError(.networkConnectionLost)
            }

            #expect(offset == 3)
            let output = try openSpeechAssetOutput(
                at: partial, statusCode: 206, requestedOffset: offset)
            try output.write(contentsOf: file.suffix(from: Int(offset)))
            try output.close()
            onProgress(Int64(file.count))
            return try #require(
                HTTPURLResponse(
                    url: url, statusCode: 206, httpVersion: "HTTP/1.1", headerFields: [:]))
        }

        do {
            try await fetchPinnedFile(
                repository: "test/model", revision: "pinned", path: "weights.bin",
                destination: root.appending(path: "weights.bin"), expected: expected,
                downloader: downloader
            ) { _ in }
            Issue.record("The first interrupted request should fail")
        } catch is URLError {
        }

        try await fetchPinnedFile(
            repository: "test/model", revision: "pinned", path: "weights.bin",
            destination: root.appending(path: "weights.bin"), expected: expected,
            downloader: downloader
        ) { bytes in progress.withLock { $0.append(bytes) } }

        #expect(requests.withLock { $0 } == [0, 3])
        #expect(ranges.withLock { $0 } == [nil, "bytes=3-"])
        #expect(progress.withLock { $0 } == [Int64(file.count), Int64(file.count)])
        #expect(try Data(contentsOf: root.appending(path: "weights.bin")) == file)
    }

    @Test("restarts a partial file when the server refuses a range request")
    func restartsWhenRangeIsRefused() async throws {
        let sandbox = Sandbox()
        let root = sandbox.root
        let file = Data([1, 2, 3, 4, 5, 6])
        let digest = SHA256.hash(data: file).map { String(format: "%02x", $0) }.joined()
        let expected = SpeechModelFile(bytes: Int64(file.count), sha256: digest)
        let requests = Mutex<[Int64]>([])
        let ranges = Mutex<[String?]>([])
        let downloader: SpeechAssetDownloader = { request, partial, offset, _ in
            requests.withLock { $0.append(offset) }
            ranges.withLock { $0.append(request.value(forHTTPHeaderField: "Range")) }
            guard let url = request.url else { throw URLError(.badURL) }
            try FileManager.default.createDirectory(
                at: partial.deletingLastPathComponent(), withIntermediateDirectories: true)
            if offset > 0 {
                let output = try openSpeechAssetOutput(
                    at: partial, statusCode: 200, requestedOffset: offset)
                try output.write(contentsOf: file)
                try output.close()
                return try #require(
                    HTTPURLResponse(
                        url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:]))
            }
            let output = try openSpeechAssetOutput(at: partial, statusCode: 200, requestedOffset: 0)
            try output.write(contentsOf: file)
            try output.close()
            return try #require(
                HTTPURLResponse(
                    url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:]))
        }
        let partial = root.appending(path: ".weights.bin.partial")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(file.prefix(3)).write(to: partial)

        try await fetchPinnedFile(
            repository: "test/model", revision: "pinned", path: "weights.bin",
            destination: root.appending(path: "weights.bin"), expected: expected,
            downloader: downloader
        ) { _ in }

        #expect(requests.withLock { $0 } == [3])
        #expect(ranges.withLock { $0 } == ["bytes=3-"])
        #expect(try Data(contentsOf: root.appending(path: "weights.bin")) == file)
    }

    @Test("restarts from zero when a resumed file fails its digest check")
    func restartsWhenResumedDigestDoesNotMatch() async throws {
        let sandbox = Sandbox()
        let root = sandbox.root
        let file = Data([1, 2, 3, 4, 5, 6])
        let digest = SHA256.hash(data: file).map { String(format: "%02x", $0) }.joined()
        let expected = SpeechModelFile(bytes: Int64(file.count), sha256: digest)
        let offsets = Mutex<[Int64]>([])
        let ranges = Mutex<[String?]>([])
        let downloader: SpeechAssetDownloader = { request, partial, offset, _ in
            offsets.withLock { $0.append(offset) }
            ranges.withLock { $0.append(request.value(forHTTPHeaderField: "Range")) }
            guard let url = request.url else { throw URLError(.badURL) }
            if offset > 0 {
                let output = try openSpeechAssetOutput(
                    at: partial, statusCode: 206, requestedOffset: offset)
                try output.write(contentsOf: file.suffix(from: Int(offset)))
                try output.close()
                return try #require(
                    HTTPURLResponse(
                        url: url, statusCode: 206, httpVersion: "HTTP/1.1", headerFields: [:]))
            }
            let output = try openSpeechAssetOutput(at: partial, statusCode: 200, requestedOffset: 0)
            try output.write(contentsOf: file)
            try output.close()
            return try #require(
                HTTPURLResponse(
                    url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:]))
        }
        let partial = root.appending(path: ".weights.bin.partial")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data([9, 9, 9]).write(to: partial)

        try await fetchPinnedFile(
            repository: "test/model", revision: "pinned", path: "weights.bin",
            destination: root.appending(path: "weights.bin"), expected: expected,
            downloader: downloader
        ) { _ in }

        #expect(offsets.withLock { $0 } == [3, 0])
        #expect(ranges.withLock { $0 } == ["bytes=3-", nil])
        #expect(try Data(contentsOf: root.appending(path: "weights.bin")) == file)
    }
}
