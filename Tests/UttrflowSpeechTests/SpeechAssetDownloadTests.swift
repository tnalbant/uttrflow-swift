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
        let downloader: SpeechAssetDownloader = { url, onProgress in
            onProgress(2)
            onProgress(4)
            #expect(reports.withLock { $0 } == [2, 4])
            #expect(!finishedTransport.withLock { $0 })
            let temporary = root.appending(path: "download")
            try FileManager.default.createDirectory(
                at: root, withIntermediateDirectories: true)
            try file.write(to: temporary)
            let response = try #require(
                HTTPURLResponse(
                    url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:]))
            finishedTransport.withLock { $0 = true }
            return (temporary, response)
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
}
