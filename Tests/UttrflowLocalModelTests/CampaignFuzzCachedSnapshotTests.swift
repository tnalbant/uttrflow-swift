// Campaign fuzz: CachedSnapshot over hostile cache directories. Not for commit.
import Foundation
import Testing

@testable import UttrflowLocalModel

private struct CampaignRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private enum Hostile {
    static func safetensors(headerLength: UInt64, header: Data, payload: Int) -> Data {
        var length = headerLength.littleEndian
        var file = Data(bytes: &length, count: 8)
        file.append(header)
        file.append(Data(repeating: 7, count: payload))
        return file
    }

    static func header(end: String, extra: String = "") -> Data {
        Data(#"{"w":{"dtype":"U8","shape":[1],"data_offsets":[0,\#(end)]}\#(extra)}"#.utf8)
    }

    /// An independent, overflow-safe reading of what a whole file is.
    static func referenceWhole(_ data: Data) -> Bool {
        guard data.count > 8 else { return false }
        let headerLength = data.prefix(8).enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << (8 * $1.offset) }
        guard headerLength > 0, headerLength <= 100_000_000, UInt64(data.count) >= 8 + headerLength else { return false }
        let header = data.subdata(in: 8..<(8 + Int(headerLength)))
        guard let tensors = try? JSONSerialization.jsonObject(with: header) as? [String: Any] else { return false }
        let end = tensors.values.compactMap { ($0 as? [String: Any])?["data_offsets"] as? [UInt64] }.compactMap(\.last).max() ?? 0
        let (sum, overflow) = (8 + headerLength).addingReportingOverflow(end)
        return !overflow && sum == UInt64(data.count)
    }
}

@Suite("CampaignFuzz cached snapshot", .serialized)
struct CampaignFuzzCachedSnapshotTests {
    private let identifier = "example-org/tiny-model"
    private let commit = String(repeating: "b2", count: 20)

    private func layout() throws -> (root: URL, snapshot: URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "campaign-snapshot-\(UUID().uuidString)")
        let repository = root.appending(path: "models--example-org--tiny-model")
        let snapshot = repository.appending(path: "snapshots/\(commit)")
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repository.appending(path: "refs"), withIntermediateDirectories: true)
        try Data((commit + "\n").utf8).write(to: repository.appending(path: "refs/main"))
        for name in CachedSnapshot.requiredFiles { try Data("{}".utf8).write(to: snapshot.appending(path: name)) }
        return (root, snapshot)
    }

    @Test("a data_offsets end near UInt64.max is refused, not trapped")
    func hugeEndOffset() throws {
        let (root, snapshot) = try layout()
        defer { try? FileManager.default.removeItem(at: root) }
        let header = Hostile.header(end: "18446744073709551615")
        let file = snapshot.appending(path: "model.safetensors")
        try Hostile.safetensors(headerLength: UInt64(header.count), header: header, payload: 16).write(to: file)
        #expect(CachedSnapshot.wholeSize(of: file) == nil)
    }

    @Test("hostile safetensors headers, symlink loops and shard names", .timeLimit(.minutes(20)))
    func hostileDirectories() throws {
        var rng = CampaignRNG(state: 0x5EED_0101)
        let skipOverflow = ProcessInfo.processInfo.environment["CAMPAIGN_SKIP_OVERFLOW"] != nil
        let ends = ["0", "1", "16", "-1", "1.5", "\"16\"", "null", "[]", "18446744073709551616", "9223372036854775807",
                    "9223372036854775808", "1e400", "18446744073709551000"] + (skipOverflow ? [] : ["18446744073709551615", "18446744073709551600"])
        var iterations = 0
        var accepted = 0
        var mismatches = 0
        for round in 0..<3_000 {
            let (root, snapshot) = try layout()
            defer { try? FileManager.default.removeItem(at: root) }
            let files = Int.random(in: 1...4, using: &rng)
            var expectedWhole = true
            for index in 0..<files {
                let name: String
                switch Int.random(in: 0...5, using: &rng) {
                case 0: name = "model.safetensors"
                case 1: name = "model-0000\(index + 1)-of-0000\(files).safetensors"
                case 2: name = "model-\(index + 1)-of-\(Int.random(in: 0...99_999, using: &rng)).safetensors"
                case 3: name = "model-00001-of-\(String(repeating: "9", count: Int.random(in: 1...40, using: &rng))).safetensors"
                case 4: name = "x-٣-of-٣.safetensors"
                default: name = "shard\(index).safetensors"
                }
                let url = snapshot.appending(path: name)
                if (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil { continue }
                switch Int.random(in: 0...9, using: &rng) {
                case 0:
                    try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: name)
                    expectedWhole = false
                case 1:
                    let other = snapshot.appending(path: "loop-\(index)")
                    try? FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: other.lastPathComponent)
                    try? FileManager.default.createSymbolicLink(atPath: other.path, withDestinationPath: name)
                    expectedWhole = false
                case 2:
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    expectedWhole = false
                default:
                    let payload = Int.random(in: 0...64, using: &rng)
                    let end = Bool.random(using: &rng) ? String(payload) : ends.randomElement(using: &rng)!
                    var header = Hostile.header(end: end)
                    switch Int.random(in: 0...6, using: &rng) {
                    case 0: header = header.prefix(Int.random(in: 0...header.count, using: &rng))
                    case 1: header = Data((0..<Int.random(in: 0...64, using: &rng)).map { _ in UInt8.random(in: 0...255, using: &rng) })
                    case 2: header = Data(("[" + String(repeating: "[", count: 5_000) + "]").utf8)
                    default: break
                    }
                    let declared: UInt64
                    switch Int.random(in: 0...6, using: &rng) {
                    case 0: declared = UInt64.max
                    case 1: declared = 0
                    case 2: declared = UInt64(header.count) + UInt64(Int.random(in: 1...100, using: &rng))
                    case 3: declared = 100_000_001
                    case 4: declared = UInt64.random(in: 0...UInt64.max, using: &rng)
                    default: declared = UInt64(header.count)
                    }
                    let data = Hostile.safetensors(headerLength: declared, header: header, payload: payload)
                    let cut = Int.random(in: 0...4, using: &rng) == 0 ? data.prefix(Int.random(in: 0...data.count, using: &rng)) : data
                    try Data(cut).write(to: url)
                    if !Hostile.referenceWhole(Data(cut)) { expectedWhole = false }
                    let single = CachedSnapshot.wholeSize(of: url)
                    if (single != nil) != Hostile.referenceWhole(Data(cut)) {
                        mismatches += 1
                        Issue.record("round \(round): wholeSize disagrees with reference for \(name)")
                    }
                }
            }
            if Int.random(in: 0...5, using: &rng) == 0 {
                try FileManager.default.removeItem(at: snapshot.appending(path: "tokenizer.json"))
                try FileManager.default.createSymbolicLink(
                    atPath: snapshot.appending(path: "tokenizer.json").path, withDestinationPath: "tokenizer.json")
                expectedWhole = false
            }
            let result = CachedSnapshot.complete(identifier: identifier, in: root, minimumWeightBytes: 0)
            iterations += 1
            if let result {
                accepted += 1
                #expect(result.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path))
                if !expectedWhole {
                    Issue.record("round \(round): accepted a snapshot the reference calls incomplete")
                }
            }
        }
        print("CAMPAIGN cachedSnapshot iterations=\(iterations) accepted=\(accepted) mismatches=\(mismatches)")
    }

    @Test("hostile refs/main")
    func hostileRefs() throws {
        let (root, _) = try layout()
        defer { try? FileManager.default.removeItem(at: root) }
        let refs = root.appending(path: "models--example-org--tiny-model/refs/main")
        let values = ["", "../../../../etc", String(repeating: "a", count: 39) + "/", String(repeating: "g", count: 40),
                      String(repeating: "ａ", count: 40), String(repeating: "A", count: 40), String(repeating: "0", count: 5_000_000)]
        for value in values {
            try Data(value.utf8).write(to: refs)
            #expect(CachedSnapshot.complete(identifier: identifier, in: root, minimumWeightBytes: 0) == nil)
        }
        try FileManager.default.removeItem(at: refs)
        try FileManager.default.createSymbolicLink(atPath: refs.path, withDestinationPath: "main")
        #expect(CachedSnapshot.complete(identifier: identifier, in: root, minimumWeightBytes: 0) == nil)
        print("CAMPAIGN hostileRefs cases=\(values.count + 1)")
    }
}
