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

/// Tracks overlapping native menus independently of focused-element changes.
struct NativeMenuVisibilityState<Element: Hashable> {
    private(set) var focusedElement: Element?
    private var openMenuCount = 0

    var isOpen: Bool { openMenuCount > 0 }

    mutating func focusedElementChanged(to element: Element?) {
        focusedElement = element
    }

    mutating func menuOpened() {
        openMenuCount += 1
    }

    mutating func menuClosed() {
        guard openMenuCount > 0 else { return }
        openMenuCount -= 1
    }

    @discardableResult
    mutating func reset() -> Bool {
        let wasOpen = isOpen
        focusedElement = nil
        openMenuCount = 0
        return wasOpen
    }
}

private struct AXElementIdentity: Hashable {
    let element: AXUIElement

    static func == (lhs: Self, rhs: Self) -> Bool { CFEqual(lhs.element, rhs.element) }

    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
}

/// Keeps open and close notifications registered as a pair.
@discardableResult
func registerPairedNativeMenuNotifications(
    registerOpened: () -> Bool,
    registerClosed: () -> Bool,
    removeOpened: () -> Void,
    removeClosed: () -> Void
) -> Bool {
    let openedWasRegistered = registerOpened()
    let closedWasRegistered = registerClosed()
    guard openedWasRegistered, closedWasRegistered else {
        if openedWasRegistered { removeOpened() }
        if closedWasRegistered { removeClosed() }
        return false
    }
    return true
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
    private var nativeMenuState = NativeMenuVisibilityState<AXElementIdentity>()

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
        removeObserver()
        onValueChanged = nil
        onNativeMenuVisibilityChanged = nil
    }

    private func observeFrontmostApplication() {
        guard let app = NSWorkspace.shared.frontmostApplication,
            app.bundleIdentifier != Bundle.main.bundleIdentifier
        else {
            removeObserver()
            return
        }

        if processIdentifier != app.processIdentifier { installObserver(for: app) }
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
        // Application-level AX registration receives notifications from every app element.
        let context = Unmanaged.passUnretained(self).toOpaque()
        registerPairedNativeMenuNotifications(
            registerOpened: {
                AXObserverAddNotification(
                    created, application, kAXMenuOpenedNotification as CFString, context) == .success
            },
            registerClosed: {
                AXObserverAddNotification(
                    created, application, kAXMenuClosedNotification as CFString, context) == .success
            },
            removeOpened: {
                _ = AXObserverRemoveNotification(
                    created, application, kAXMenuOpenedNotification as CFString)
            },
            removeClosed: {
                _ = AXObserverRemoveNotification(
                    created, application, kAXMenuClosedNotification as CFString)
            })
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
            setFocusedElement(nil)
            return
        }
        let focused = unsafeDowncast(value, to: AXUIElement.self)
        if let focusedElement, CFEqual(focusedElement, focused) { return }
        setFocusedElement(focused)
    }

    private func setFocusedElement(_ focused: AXUIElement?) {
        guard let observer else { return }
        if let focusedElement {
            _ = AXObserverRemoveNotification(
                observer, focusedElement, kAXValueChangedNotification as CFString)
        }
        focusedElement = focused
        nativeMenuState.focusedElementChanged(to: focused.map(AXElementIdentity.init))
        if let focused {
            _ = AXUIElementSetMessagingTimeout(focused, 0.2)
            _ = AXObserverAddNotification(
                observer, focused, kAXValueChangedNotification as CFString,
                Unmanaged.passUnretained(self).toOpaque())
        }
    }

    private func removeObserver() {
        resetNativeMenuState()
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
        if let focusedElement {
            _ = AXObserverRemoveNotification(
                observer, focusedElement, kAXValueChangedNotification as CFString)
        }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        self.observer = nil
        application = nil
        processIdentifier = nil
    }

    private func resetNativeMenuState() {
        if nativeMenuState.reset() { onNativeMenuVisibilityChanged?(false) }
    }

    fileprivate func received(_ notification: String) {
        if notification == kAXFocusedUIElementChangedNotification as String {
            updateFocusedElement()
        } else if notification == kAXValueChangedNotification as String {
            onValueChanged?()
        } else if notification == kAXMenuOpenedNotification as String {
            let wasOpen = nativeMenuState.isOpen
            nativeMenuState.menuOpened()
            if !wasOpen { onNativeMenuVisibilityChanged?(true) }
        } else if notification == kAXMenuClosedNotification as String {
            let wasOpen = nativeMenuState.isOpen
            nativeMenuState.menuClosed()
            if wasOpen && !nativeMenuState.isOpen { onNativeMenuVisibilityChanged?(false) }
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
