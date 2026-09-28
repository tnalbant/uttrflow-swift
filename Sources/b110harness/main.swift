import AVFoundation
import AppKit
import Foundation
import UttrflowAudio
import UttrflowCore

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e6 }

final class Probe: @unchecked Sendable {
    let lock = NSLock()
    var firstTap: Double?; var firstTapCount = 0; var firstLoud: Double?; var loudIndex = 0; var total = 0
    func reset() { lock.lock(); firstTap = nil; firstLoud = nil; total = 0; lock.unlock() }
    func saw(_ s: [Float]) {
        let t = now(); lock.lock(); defer { lock.unlock() }
        if firstTap == nil { firstTap = t; firstTapCount = s.count }
        if firstLoud == nil, let i = s.firstIndex(where: { abs($0) > 1e-5 }) { firstLoud = t; loudIndex = total + i }
        total += s.count
    }
}

final class Wrapped: MicrophoneSource, @unchecked Sendable {
    let inner = AVAudioEngineMicrophoneSource(); let probe: Probe
    init(_ p: Probe) { probe = p }
    func start(onSamples: @escaping @Sendable ([Float]) -> Void, onInterruption: @escaping @Sendable (CaptureInterruption) -> Void) throws(AudioCaptureError) {
        let p = probe
        try inner.start(onSamples: { p.saw($0); onSamples($0) }, onInterruption: onInterruption)
    }
    func stop(draining: Bool) async { await inner.stop(draining: draining) }
}

let args = CommandLine.arguments
let mode = args[1]; let n = Int(args[2])!; let idle = Double(args[3])!; let hold = Double(args[4])!
print("mic auth:", AVCaptureDevice.authorizationStatus(for: .audio).rawValue)
if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
    let ok = await AVCaptureDevice.requestAccess(for: .audio); print("requested:", ok)
}
let probe = Probe()
let engine = AVAudioCaptureEngine(source: Wrapped(probe))
let cue = NSSound(named: "Tink")
print("mode,i,start,cue,firstTap,firstTapFrames,captureBegins,firstLoud")
for i in 0..<n {
    if i > 0 || mode == "cold" { try await Task.sleep(for: .milliseconds(Int(idle * 1000))) }
    probe.reset()
    let t0 = now()
    if hold > 0 { try await Task.sleep(for: .milliseconds(Int(hold))) }
    do { try await engine.start() } catch { print("start error", error); exit(1) }
    let tStart = now()
    cue?.stop(); cue?.play()
    let tCue = now()
    try await Task.sleep(for: .milliseconds(800))
    let s = try await engine.stop()
    let (ft, fl, c) = probe.lock.withLock { (probe.firstTap ?? -1, probe.firstLoud ?? -1, probe.firstTapCount) }
    let begins = ft - Double(c) / 16.0
    print(String(format: "%@,%d,%.1f,%.1f,%.1f,%d,%.1f,%.1f,%d", mode, i, tStart - t0, tCue - t0, ft - t0, c, begins - t0, fl - t0, s.samples.count))
}
