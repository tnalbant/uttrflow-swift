import AppKit
import ApplicationServices
import Foundation

@MainActor
protocol FocusedFieldValueObserving: AnyObject {
    func start(
        onValueChanged: @escaping @MainActor () -> Void,
        onNativeMenuVisibilityChanged: @escaping @MainActor (Bool) -> Void)
    func refresh()
    func stop()
}

/// Observes value changes on the external application's currently focused Accessibility element.
@MainActor
final class FocusedFieldValueObserver: FocusedFieldValueObserving {
    private var observer: AXObserver?
    private var application: AXUIElement?
    private var focusedElement: AXUIElement?
    private var processIdentifier: pid_t?
    private var onValueChanged: (@MainActor () -> Void)?
    private var onNativeMenuVisibilityChanged: (@MainActor (Bool) -> Void)?
    private var nativeMenuIsOpen = false

    isolated deinit { stop() }

    func start(
        onValueChanged: @escaping @MainActor () -> Void,
        onNativeMenuVisibilityChanged: @escaping @MainActor (Bool) -> Void
    ) {
        self.onValueChanged = onValueChanged
        self.onNativeMenuVisibilityChanged = onNativeMenuVisibilityChanged
        observeFrontmostApplication()
    }

    func refresh() {
        guard onValueChanged != nil else { return }
        observeFrontmostApplication()
    }

    func stop() {
        updateNativeMenuVisibility(false)
        removeObserver()
        onValueChanged = nil
        onNativeMenuVisibilityChanged = nil
    }

    private func observeFrontmostApplication() {
        guard let app = NSWorkspace.shared.frontmostApplication,
            app.bundleIdentifier != Bundle.main.bundleIdentifier
        else {
            updateNativeMenuVisibility(false)
            removeObserver()
            return
        }

        if processIdentifier != app.processIdentifier {
            updateNativeMenuVisibility(false)
            installObserver(for: app)
        }
        updateFocusedElement()
    }

    private func installObserver(for app: NSRunningApplication) {
        removeObserver()
        var created: AXObserver?
        guard AXObserverCreate(app.processIdentifier, focusedFieldAXObserverCallback, &created) == .success,
            let created
        else { return }

        let application = AXUIElementCreateApplication(app.processIdentifier)
        _ = AXUIElementSetMessagingTimeout(application, 0.2)
        observer = created
        self.application = application
        processIdentifier = app.processIdentifier
        CFRunLoopAddSource(
            CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        _ = AXObserverAddNotification(
            created, application, kAXFocusedUIElementChangedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque())
        _ = AXObserverAddNotification(
            created, application, kAXMenuOpenedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque())
        _ = AXObserverAddNotification(
            created, application, kAXMenuClosedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque())
    }

    private func updateFocusedElement() {
        guard let observer, let application else { return }
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                application, kAXFocusedUIElementAttribute as CFString, &value) == .success,
            let value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            removeFocusedElementObserver()
            return
        }
        let focused = unsafeDowncast(value, to: AXUIElement.self)
        if let focusedElement, CFEqual(focusedElement, focused) { return }
        removeFocusedElementObserver()
        focusedElement = focused
        _ = AXUIElementSetMessagingTimeout(focused, 0.2)
        _ = AXObserverAddNotification(
            observer, focused, kAXValueChangedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque())
        _ = AXObserverAddNotification(
            observer, focused, kAXMenuOpenedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque())
        _ = AXObserverAddNotification(
            observer, focused, kAXMenuClosedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque())
    }

    private func removeObserver() {
        guard let observer else {
            application = nil
            focusedElement = nil
            processIdentifier = nil
            return
        }
        if let application {
            _ = AXObserverRemoveNotification(
                observer, application, kAXFocusedUIElementChangedNotification as CFString)
            _ = AXObserverRemoveNotification(
                observer, application, kAXMenuOpenedNotification as CFString)
            _ = AXObserverRemoveNotification(
                observer, application, kAXMenuClosedNotification as CFString)
        }
        removeFocusedElementObserver()
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        self.observer = nil
        application = nil
        processIdentifier = nil
    }

    private func removeFocusedElementObserver() {
        if let observer, let focusedElement {
            _ = AXObserverRemoveNotification(
                observer, focusedElement, kAXValueChangedNotification as CFString)
            _ = AXObserverRemoveNotification(
                observer, focusedElement, kAXMenuOpenedNotification as CFString)
            _ = AXObserverRemoveNotification(
                observer, focusedElement, kAXMenuClosedNotification as CFString)
        }
        focusedElement = nil
    }

    private func updateNativeMenuVisibility(_ isOpen: Bool) {
        guard nativeMenuIsOpen != isOpen else { return }
        nativeMenuIsOpen = isOpen
        onNativeMenuVisibilityChanged?(isOpen)
    }

    fileprivate func received(_ notification: String) {
        if notification == kAXFocusedUIElementChangedNotification as String {
            updateFocusedElement()
        } else if notification == kAXValueChangedNotification as String {
            onValueChanged?()
        } else if notification == kAXMenuOpenedNotification as String {
            updateNativeMenuVisibility(true)
        } else if notification == kAXMenuClosedNotification as String {
            updateNativeMenuVisibility(false)
        }
    }
}

private func focusedFieldAXObserverCallback(
    _ observer: AXObserver, _ element: AXUIElement, _ notification: CFString,
    _ context: UnsafeMutableRawPointer?
) {
    guard let context else { return }
    let valueObserver = Unmanaged<FocusedFieldValueObserver>.fromOpaque(context).takeUnretainedValue()
    let notificationName = notification as String
    MainActor.assumeIsolated { valueObserver.received(notificationName) }
}
