// Local render harness; never committed.

import AppKit
import Foundation
import SwiftUI
import Testing
import UttrflowCore
@testable import UttrflowUX

@testable import Uttrflow

@MainActor
@Suite("ZZ onboarding shots", .serialized)
struct ZZOnboardingShots {
    @Test("render")
    func render() async throws {
        guard let out = ProcessInfo.processInfo.environment["PARITY_OUT"] else { return }
        try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        _ = BrandFont.isAvailable
        let hotkey = HotkeyBinding.controlOptionHold
        let states: [(String, OnboardingState)] = [
            ("signin-offering", OnboardingState(step: .signIn, detail: .signIn(.offering))),
            ("signin-browser", OnboardingState(step: .signIn, detail: .signIn(.signingIn(.google)))),
            ("signin-refused", OnboardingState(step: .signIn, detail: .signIn(.refused("Nobody answered.")))),
            ("signin-unreachable", OnboardingState(step: .signIn, detail: .signIn(.unreachable))),
            ("mic-ask", OnboardingState(step: .microphone, detail: .permission(.notDetermined))),
            ("mic-waiting", OnboardingState(step: .microphone, detail: .awaitingSystemSettings)),
            ("mic-denied", OnboardingState(step: .microphone, detail: .permission(.denied))),
            ("mic-granted", OnboardingState(step: .microphone, detail: .permission(.granted))),
            ("ax-ask", OnboardingState(step: .accessibility, detail: .permission(.notDetermined))),
            ("ax-granted", OnboardingState(step: .accessibility, detail: .permission(.granted))),
            ("setup-installing", OnboardingState(step: .setup, detail: .installing(0.62))),
            ("setup-failed", OnboardingState(step: .setup, detail: .installFailed("Check your connection.", reached: 0.38))),
            ("setup-installed", OnboardingState(step: .setup, detail: .installed)),
            ("ready", OnboardingState(step: .ready, detail: .finishing(.ready))),
            ("ready-listening", OnboardingState(step: .ready, detail: .finishing(.ready, trial: .listening))),
            ("ready-heard", OnboardingState(step: .ready, detail: .finishing(.ready, trial: .heard("Hello Uttrflow, this works.")))),
        ]
        let size = CGSize(width: OnboardingMetrics.windowWidth, height: OnboardingMetrics.windowHeight)
        // Waits for the aurora's turn to sit near where the mock was captured.
        while Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 40) > 0.6
            || Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 40) < 0.3
        {
            try? await Task.sleep(for: .milliseconds(20))
        }
        var shots: [(String, NSHostingView<OnboardingScreen>, NSWindow)] = []
        for (name, state) in states {
            let page = OnboardingPresenter.page(for: state, hotkey: hotkey)
            let hosting = NSHostingView(rootView: OnboardingScreen(page: page, press: { _ in }))
            hosting.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = hosting
            shots.append((name, hosting, window))
        }
        for _ in 0..<6 { try? await Task.sleep(for: .milliseconds(60)) }
        for (name, hosting, window) in shots {
            hosting.layoutSubtreeIfNeeded()
            if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(
                    to: URL(fileURLWithPath: "\(out)/onboarding--\(name)--dark.png"))
            }
            window.close()
        }
    }
}
