// Local render harness; never committed.

import AppKit
import Foundation
import SwiftUI
import Testing
import UttrflowUX
import UttrflowHistory
import UttrflowSettings
import UttrflowCore

@testable import Uttrflow

@MainActor
@Suite("ZZ drift shots", .serialized)
struct ZZDriftShots {
    @Test("render")
    func render() async throws {
        guard let out = ProcessInfo.processInfo.environment["DRIFT_OUT"] else { return }
        try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        _ = BrandFont.isAvailable
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        let real = app.makeMainWindow()
        app.mainWindow = real
        real.show(.home)
        let window = try #require(Mirror(reflecting: real).descendant("window") as? NSWindow)
        defer { window.close() }
        window.setContentSize(NSSize(width: 1180, height: 780))
        for (theme, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            window.appearance = NSAppearance(named: appearance)
            for (name, intent) in [("home-empty", MainIntent.show(.home)), ("history-empty", .show(.history))] {
                app.carryOut(intent)
                for _ in 0..<12 { try? await Task.sleep(for: .milliseconds(60)) }
                guard let view = window.contentView else { continue }
                view.layoutSubtreeIfNeeded()
                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: "\(out)/\(name)-\(theme).png"))
            }
        }
    }

    @Test("home direct")
    func homeDirect() async throws {
        guard let out = ProcessInfo.processInfo.environment["DRIFT_OUT"] else { return }
        try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        _ = BrandFont.isAvailable
        let now = Date(timeIntervalSince1970: 1_750_000_800)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/London")!
        let perms: [PermissionKind: PermissionStatus] = [.microphone: .granted, .accessibility: .granted]
        let entry = HistoryEntry(
            id: UUID(), text: "Let's move the review to Thursday afternoon.", when: now.addingTimeInterval(-600),
            applicationName: "Slack", applicationIdentifier: nil, changes: RecordedChanges(), isFlagged: false)
        let pages: [(String, HomePresentation)] = [
            ("home-empty-direct", HomePresenter.page(
                for: HomeSnapshot(permissions: perms, entries: [], shortcut: "⌥Space", now: now),
                calendar: cal, locale: Locale(identifier: "en_GB"))),
            ("home-full-direct", HomePresenter.page(
                for: HomeSnapshot(permissions: perms, entries: [entry], shortcut: "⌥Space", now: now),
                calendar: cal, locale: Locale(identifier: "en_GB"))),
        ]
        for (theme, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            for (name, page) in pages {
                let host = NSHostingView(rootView: HomePageView(presentation: page).background(Color.redesignWindow))
                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled],
                    backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: appearance)
                window.isReleasedWhenClosed = false
                window.contentView = host
                window.orderFront(nil)
                for _ in 0..<10 { try? await Task.sleep(for: .milliseconds(60)) }
                host.layoutSubtreeIfNeeded()
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: "\(out)/\(name)-\(theme).png"))
                }
                window.close()
            }
        }
    }
}
