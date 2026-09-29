// Reopening the panel keeps its restored selection in the visible part of the list.

import AppKit
import ApplicationServices
import SwiftUI
import Testing
import UttrflowClipboard
import UttrflowUX

@testable import Uttrflow

@MainActor
@Suite(
    "Restoring a quick panel selection",
    .enabled(if: AXIsProcessTrusted(), "SwiftUI builds its accessibility tree for a trusted client"),
    .serialized
)
struct QuickPanelScrollRestoreTests {
    private func elements(under root: AnyObject) -> [AnyObject] {
        let children = (root.accessibilityChildren?() ?? []).map { $0 as AnyObject }
        return [root] + children.flatMap { elements(under: $0) }
    }

    private func askAsAnAssistiveApp() {
        let done = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            var value: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(
                AXUIElementCreateApplication(getpid()), kAXChildrenAttribute as CFString, &value)
            done.signal()
        }
        let deadline = Date().addingTimeInterval(5)
        while done.wait(timeout: .now()) == .timedOut && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    }

    @Test("the restored row is inside the list viewport on reopen")
    func restoredSelectionScrollsIntoView() async throws {
        let now = Date()
        let clips = (0..<40).map { index in
            Clip(
                text: "clip-\(index)", kind: .text,
                copiedAt: now.addingTimeInterval(TimeInterval(-index)))
        }
        let selected = try #require(clips.last)
        let snapshot = PanelSnapshot(clips: clips, selection: selected.id, now: now)
        let presentation = PanelPresenter.present(snapshot)
        let label = QuickPanelSpeech.label(for: try #require(presentation.selectedRow))

        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 420, height: 360),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: QuickPanelView(presentation: presentation, openCount: 1))
        window.contentView = host
        window.orderFrontRegardless()

        try await Task.sleep(for: .milliseconds(250))
        askAsAnAssistiveApp()

        let scrollView = try #require(
            host.subviews
                .flatMap { descendants(of: $0) }
                .compactMap { $0 as? NSScrollView }
                .first { $0.bounds.height > 100 && $0.bounds.width > 300 })
        let scrollFrame = window.convertToScreen(scrollView.convert(scrollView.bounds, to: nil))
        let row = try #require(
            elements(under: host).first { ($0.accessibilityLabel?() ?? nil) == label })
        let rowFrame = try #require(row.accessibilityFrame?() ?? nil)

        #expect(rowFrame.intersects(scrollFrame))
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }
}
