// Tests that a page explanation belongs to the heading rather than every control on the card.

import AppKit
import ApplicationServices
import SwiftUI
import UttrflowSettings
import Testing
import UttrflowUX

@testable import Uttrflow

@MainActor
@Suite(
    "Onboarding card accessibility",
    .enabled(if: AXIsProcessTrusted(), "SwiftUI builds its tree only for a trusted client"))
struct OnboardingCardAccessibilityTests {
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

    @Test("page explanation is announced by the heading and not repeated as control help")
    func explanationStaysOnTheHeading() {
        let page = OnboardingPresenter.page(
            for: OnboardingState(step: .signIn, detail: .signIn(.signingIn(.google))),
            hotkey: Settings.default.hotkey)
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        let window = NSWindow(
            contentRect: NSRect(x: -4_000, y: -4_000, width: OnboardingMetrics.cardWidth, height: 500),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }

        let host = NSHostingView(rootView: OnboardingCard(page: page, press: { _ in }))
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        askAsAnAssistiveApp()

        let found = elements(under: host)
        let headings = found.filter { $0.accessibilityRole?() == .heading }
        let buttons = found.filter { $0.accessibilityRole?() == .button }
        let indicators = found.filter { $0.accessibilityLabel?() == "Step 1 of 5: Sign in" }
        #expect(headings.contains { ($0.accessibilityLabel?() ?? "").contains(page.explanation ?? "") })
        #expect(Set(buttons.compactMap { $0.accessibilityLabel?() }).isSuperset(of: ["Reopen", "Cancel"]))
        #expect(indicators.count == 1)
        #expect((buttons + indicators).allSatisfy { ($0.accessibilityHelp?() ?? nil) == nil })
    }
}
