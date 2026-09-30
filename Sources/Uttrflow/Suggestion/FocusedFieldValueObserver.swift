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

/// Tracks overlapping native menus and retains observed focus elements until every menu closes.
struct NativeMenuVisibilityState<Element: Hashable> {
    private(set) var focusedElement: Element?
    private var openCounts: [Element: Int] = [:]
    private var retainedFocusedElements: Set<Element> = []

    var isOpen: Bool { !openCounts.isEmpty }
    var observedFocusedElements: Set<Element> {
        retainedFocusedElements.union(focusedElement.map { [$0] } ?? [])
    }

    mutating func focusedElementChanged(to element: Element?) {
        if isOpen, let focusedElement, focusedElement != element {
            retainedFocusedElements.insert(focusedElement)
        }
        focusedElement = element
        if !isOpen { retainedFocusedElements.removeAll() }
    }

    mutating func menuOpened(from element: Element) {
        openCounts[element, default: 0] += 1
    }

    mutating func menuClosed(from element: Element) {
        guard let count = openCounts[element] else { return }
        if count > 1 {
            openCounts[element] = count - 1
        } else {
            openCounts[element] = nil
        }
        if !isOpen { retainedFocusedElements.removeAll() }
    }

    @discardableResult
    mutating func reset() -> Bool {
        let wasOpen = isOpen
        focusedElement = nil
        openCounts.removeAll()
        retainedFocusedElements.removeAll()
        return wasOpen
    }
}

private struct AXElementIdentity: Hashable {
    let element: AXUIElement

    static func == (lhs: Self, rhs: Self) -> Bool { CFEqual(lhs.element, rhs.element) }

    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
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
    private var focusedMenuElements: [AXElementIdentity: AXUIElement] = [:]

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
        synchronizeFocusedMenuObservers()
    }

    private func synchronizeFocusedMenuObservers() {
        guard let observer else { return }
        let observed = nativeMenuState.observedFocusedElements
        let obsolete = focusedMenuElements.filter { !observed.contains($0.key) }
        for (identity, element) in obsolete {
            _ = AXObserverRemoveNotification(observer, element, kAXMenuOpenedNotification as CFString)
            _ = AXObserverRemoveNotification(observer, element, kAXMenuClosedNotification as CFString)
            focusedMenuElements[identity] = nil
        }
        if let focusedElement {
            let identity = AXElementIdentity(element: focusedElement)
            if focusedMenuElements[identity] == nil {
                _ = AXObserverAddNotification(
                    observer, focusedElement, kAXMenuOpenedNotification as CFString,
                    Unmanaged.passUnretained(self).toOpaque())
                _ = AXObserverAddNotification(
                    observer, focusedElement, kAXMenuClosedNotification as CFString,
                    Unmanaged.passUnretained(self).toOpaque())
                focusedMenuElements[identity] = focusedElement
            }
        }
    }

    private func removeObserver() {
        resetNativeMenuState()
        guard let observer else {
            application = nil
            focusedElement = nil
            processIdentifier = nil
            focusedMenuElements.removeAll()
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
        for element in focusedMenuElements.values {
            _ = AXObserverRemoveNotification(observer, element, kAXMenuOpenedNotification as CFString)
            _ = AXObserverRemoveNotification(observer, element, kAXMenuClosedNotification as CFString)
        }
        focusedMenuElements.removeAll()
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        self.observer = nil
        application = nil
        processIdentifier = nil
    }

    private func resetNativeMenuState() {
        if nativeMenuState.reset() { onNativeMenuVisibilityChanged?(false) }
    }

    fileprivate func received(_ notification: String, from element: AXUIElement) {
        if notification == kAXFocusedUIElementChangedNotification as String {
            updateFocusedElement()
        } else if notification == kAXValueChangedNotification as String {
            onValueChanged?()
        } else if notification == kAXMenuOpenedNotification as String {
            let wasOpen = nativeMenuState.isOpen
            nativeMenuState.menuOpened(from: AXElementIdentity(element: element))
            if !wasOpen { onNativeMenuVisibilityChanged?(true) }
        } else if notification == kAXMenuClosedNotification as String {
            let wasOpen = nativeMenuState.isOpen
            nativeMenuState.menuClosed(from: AXElementIdentity(element: element))
            if wasOpen && !nativeMenuState.isOpen { onNativeMenuVisibilityChanged?(false) }
            synchronizeFocusedMenuObservers()
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
    MainActor.assumeIsolated { valueObserver.received(notificationName, from: element) }
}
