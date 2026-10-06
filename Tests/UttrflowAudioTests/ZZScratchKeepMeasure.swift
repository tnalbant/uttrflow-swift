import Foundation
import Testing
@testable import UttrflowAudio
import UttrflowCore

@Suite("scratch keep measure") struct ZZScratchKeepMeasure {
    @Test func measure() async throws {
        for seconds in [2, 5, 10, 30, 90, 240] {
            for keep in [false, true] {
                var times: [Duration] = []
                var bytes = 0
                for _ in 0..<5 {
                    let dir = FileManager.default.temporaryDirectory.appending(path: "keep-\(UUID())")
                    let store = RecordingStore(directory: dir)
                    let writer = try #require(await store.begin())
                    let block = [Float](repeating: 0.1, count: 1600)
                    for _ in 0..<(seconds * 10) { writer.append(block) }
                    await writer.drained()
                    let clock = ContinuousClock()
                    let start = clock.now
                    if keep {
                        let r = await store.finish(writer)
                        await store.settle(r.id)
                        _ = await store.current()
                    } else {
                        await store.abandon(writer)
                    }
                    times.append(start.duration(to: clock.now))
                    let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
                    bytes = files.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }.reduce(0, +)
                    try? FileManager.default.removeItem(at: dir)
                }
                let sorted = times.sorted()
                print("MEASURE seconds=\(seconds) keep=\(keep) median=\(sorted[2]) max=\(sorted[4]) bytesLeft=\(bytes)")
            }
        }
    }
}
