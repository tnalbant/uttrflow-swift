import AppKit
import ApplicationServices

// The hands of Scripts/web_field_probe/probe.sh. Every command talks to one process, so nothing reaches the frontmost app.
//
//   ax_write <pid> selected <text>   writes AXSelectedText, as the dictation's Accessibility route does
//   ax_write <pid> value <text>      writes AXValue as the current value plus text, the alternative attribute
//   ax_write <pid> key <character>   posts one key press carrying that character to the process
//   ax_write <pid> read              prints the field's role, value and selection

/// One attribute of an element, and the error the server answered with.
func attribute(_ element: AXUIElement, _ name: String) -> (AXError, CFTypeRef?) {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return (result, value)
}

/// The selection in UTF-16 units, or nil where the field will not say.
func selection(of element: AXUIElement) -> CFRange? {
    guard case (.success, let raw?) = attribute(element, kAXSelectedTextRangeAttribute) else { return nil }
    var range = CFRange()
    // A range attribute arrives as an AXValue.
    guard AXValueGetValue(unsafeBitCast(raw, to: AXValue.self), .cfRange, &range) else { return nil }
    return range
}

/// The fixture's field by its DOM id, for a window that is not key and so reports no focused element.
func field(under element: AXUIElement, depth: Int = 0) -> AXUIElement? {
    if attribute(element, "AXDOMIdentifier").1 as? String == "field" { return element }
    guard depth < 40, let children = attribute(element, kAXChildrenAttribute).1 as? [AXUIElement] else {
        return nil
    }
    for child in children {
        if let found = field(under: child, depth: depth + 1) { return found }
    }
    return nil
}

/// The field's role, value and selection on one line.
func describe(_ element: AXUIElement) -> String {
    let role = attribute(element, kAXRoleAttribute).1 as? String ?? "-"
    let value = (attribute(element, kAXValueAttribute).1 as? String).map { "\"\($0)\"" } ?? "nil"
    let range = selection(of: element).map { "\($0.location)+\($0.length)" } ?? "none"
    return "role=\(role) value=\(value) selection=\(range)"
}

/// Prints and exits, so every failure is one line on stderr and a non-zero status.
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count >= 3, let pid = pid_t(arguments[1]) else { fail("usage: ax_write <pid> <command> [text]") }
let command = arguments[2]
let text = arguments.count > 3 ? arguments[3] : ""

if command == "key" {
    let source = CGEventSource(stateID: .hidSystemState)
    let units = Array(text.utf16)
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: 7, keyDown: down)
        event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        event?.postToPid(pid)
        usleep(20_000)
    }
    exit(0)
}

let application = AXUIElementCreateApplication(pid)
_ = AXUIElementSetMessagingTimeout(application, 2)
// Chromium builds its web tree only for a client that asks; the suggestion loop sets the same attribute.
_ = AXUIElementSetAttributeValue(application, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
var focused = attribute(application, kAXFocusedUIElementAttribute)
for _ in 0..<20 where focused.0 != .success {
    usleep(250_000)
    focused = attribute(application, kAXFocusedUIElementAttribute)
}
let located: AXUIElement? =
    if case (.success, let element?) = focused { unsafeDowncast(element, to: AXUIElement.self) } else {
        field(under: application)
    }
guard let element = located else { fail("no field found in process \(pid)") }
print("before: \(describe(element))")
guard command != "read" else { exit(0) }

let before = selection(of: element)
let result: AXError
switch command {
case "selected":
    result = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
case "value":
    let current = attribute(element, kAXValueAttribute).1 as? String ?? ""
    result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, (current + text) as CFString)
default:
    fail("unknown command \(command)")
}
usleep(300_000)
let after = selection(of: element)
// The check `SelectionWriter` makes: the selection collapsed at the old caret plus the text.
let collapsed =
    if let before, let after { after.length == 0 && after.location == before.location + text.utf16.count } else {
        false
    }
print("write=\(result.rawValue) caret=\(collapsed ? "confirmed" : "unconfirmed")")
print("after:  \(describe(element))")
