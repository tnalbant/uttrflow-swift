import AppKit
import WebKit

// webview <url>: the WebKit half of Scripts/web_field_probe/probe.sh, a window that never takes focus from the frontmost app.
final class Delegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 640, height: 240))
        let window = NSWindow(
            contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.orderBack(nil)
        window.makeFirstResponder(view)
        self.window = window
        guard CommandLine.arguments.count > 1, let url = URL(string: CommandLine.arguments[1]) else { exit(64) }
        view.load(URLRequest(url: url))
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = Delegate()
app.delegate = delegate
app.run()
