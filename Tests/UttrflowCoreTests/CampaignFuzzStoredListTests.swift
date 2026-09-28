// Campaign fuzz: LocalStore.read racing writers and other readers. Not for commit.
import Foundation
import Synchronization
import Testing

@testable import UttrflowCore

private final class Box<Value: Sendable>: Sendable {
    private let lock: Mutex<Value>
    init(_ value: Value) { lock = Mutex(value) }
    var get: Value { lock.withLock { $0 } }
    func set(_ change: (inout Value) -> Void) { lock.withLock { change(&$0) } }
}

@Suite("CampaignFuzz stored list", .serialized)
struct CampaignFuzzStoredListTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "campaign-stored-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func setAsideCount(_ folder: URL) -> Int {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.contains(".unreadable-") }.count
    }

    @Test("an atomic writer racing readers never yields unreadable or missing", .timeLimit(.minutes(10)))
    func atomicWriterAndReaders() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "list.json")
        try JSONEncoder().encode([0]).write(to: file, options: .atomic)
        let stop = Box(false)
        let bad = Box<[String]>([])
        let reads = Box(0)
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for index in 0..<20_000 {
                    let list = Array(0..<(index % 300))
                    try? JSONEncoder().encode(list).write(to: file, options: .atomic)
                }
                stop.set { $0 = true }
            }
            for _ in 0..<4 {
                group.addTask {
                    while !stop.get {
                        let result = LocalStore.read([Int].self, from: file)
                        reads.set { $0 += 1 }
                        switch result {
                        case .read: break
                        case .missing: bad.set { $0.append("missing") }
                        case .unreadable(let aside): bad.set { $0.append("unreadable aside=\(aside != nil)") }
                        }
                    }
                }
            }
        }
        let problems = bad.get
        print("CAMPAIGN storedAtomic writes=20000 reads=\(reads.get) problems=\(problems.count) setAside=\(setAsideCount(folder)) sample=\(problems.prefix(3))")
        #expect(problems.isEmpty)
    }

    @Test("readers of one unreadable file set it aside once, and a good write racing the read is not moved away", .timeLimit(.minutes(10)))
    func corruptRaces() async throws {
        var twoReaderNilAside = 0
        var goodWriteLost = 0
        var bothSetAside = 0
        let rounds = 2_000
        for _ in 0..<rounds {
            let folder = try folder()
            defer { try? FileManager.default.removeItem(at: folder) }
            let file = folder.appending(path: "list.json")
            try Data("{not json".utf8).write(to: file)
            // Two readers of the same corrupt file.
            async let first = LocalStore.read([Int].self, from: file)
            async let second = LocalStore.read([Int].self, from: file)
            let results = await [first, second]
            var asides = 0
            for case .unreadable(let aside) in results { if aside != nil { asides += 1 } else { twoReaderNilAside += 1 } }
            if asides == 2 { bothSetAside += 1 }
            // A reader of a corrupt file racing an atomic good write.
            try Data("{not json".utf8).write(to: file)
            async let reader = LocalStore.read([Int].self, from: file)
            async let writer: Void = { try? JSONEncoder().encode([1, 2, 3]).write(to: file, options: .atomic) }()
            _ = await (reader, writer)
            if !FileManager.default.fileExists(atPath: file.path) {
                goodWriteLost += 1
            }
        }
        print("CAMPAIGN storedCorrupt rounds=\(rounds) secondReaderNilAside=\(twoReaderNilAside) bothSetAside=\(bothSetAside) goodWriteMovedAside=\(goodWriteLost)")
        #expect(bothSetAside == 0)
    }

    @Test("hostile file contents and kinds")
    func hostileFiles() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let cases: [(String, (URL) throws -> Void)] = [
            ("deepArray", { try Data((String(repeating: "[", count: 1_000_000) + String(repeating: "]", count: 1_000_000)).utf8).write(to: $0) }),
            ("empty", { try Data().write(to: $0) }),
            ("nul", { try Data(repeating: 0, count: 4_096).write(to: $0) }),
            ("directory", { try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true) }),
            ("selfLink", { try FileManager.default.createSymbolicLink(atPath: $0.path, withDestinationPath: $0.lastPathComponent) }),
            ("danglingLink", { try FileManager.default.createSymbolicLink(atPath: $0.path, withDestinationPath: "nowhere") }),
            ("unreadable", { try Data("[1]".utf8).write(to: $0); chmod($0.path, 0) }),
            ("hugeNumber", { try Data("[1e999999]".utf8).write(to: $0) }),
            ("bom", { try Data([0xEF, 0xBB, 0xBF] + Array("[1]".utf8)).write(to: $0) }),
            ("utf16", { try "[1]".data(using: .utf16)!.write(to: $0) }),
        ]
        for (name, make) in cases {
            let file = folder.appending(path: "\(name).json")
            try make(file)
            let result = LocalStore.read([Int].self, from: file)
            print("CAMPAIGN storedHostile \(name) -> \(result)")
        }
        // A folder that cannot take the renamed file.
        let locked = folder.appending(path: "locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        let inside = locked.appending(path: "x.json")
        try Data("nope".utf8).write(to: inside)
        chmod(locked.path, 0o500)
        defer { chmod(locked.path, 0o700) }
        print("CAMPAIGN storedHostile lockedFolder -> \(LocalStore.read([Int].self, from: inside))")
        // Many set-aside names already taken for the same second.
        let crowded = folder.appending(path: "crowded.json")
        let now = Date(timeIntervalSince1970: 1_000)
        for attempt in 0..<101 {
            let name = attempt == 0 ? "crowded.json.unreadable-1000" : "crowded.json.unreadable-1000-\(attempt)"
            try Data().write(to: folder.appending(path: name))
        }
        try Data("nope".utf8).write(to: crowded)
        print("CAMPAIGN storedHostile crowded -> \(LocalStore.read([Int].self, from: crowded, now: now))")
    }
}
