// The read-only clipboard the watcher polls.

public import struct Foundation.Data
public import struct UttrflowCore.PasteboardMarkers

/// The machine's clipboard, read-only; not `UttrflowInput`'s `Pasteboard`, which this module must not link.
public protocol ClipboardSource: Sendable {
    /// The number macOS increments on every write to the clipboard, the only change signal it offers.
    func changeCount() -> Int

    /// The current contents as text, or `nil` when the clipboard holds something else.
    func text() -> String?
    /// The RTF flavour, read only when the clipboard has no plain text.
    func rtf() -> Data?
    /// The formatted flavour, read alongside the plain one, never instead of it.
    func html() -> String?

    /// The nspasteboard.org markers on the current contents, read once per change.
    func markers() -> PasteboardMarkers

    /// The picture on the clipboard as PNG bytes and pixel size, read for copies that may have text or RTF.
    func image() -> (data: Data, width: Int, height: Int)?
    /// Whether the current pasteboard advertises a picture flavour without reading its bytes.
    func hasPicture() -> Bool

    /// The application in front of the user, shown as best-effort provenance.
    func frontmostApplicationName() -> String?

    /// Bundle identifier of the frontmost application when the copy is detected. macOS does not
    /// identify the process that wrote the pasteboard, so this is best-effort provenance only.
    func frontmostApplicationBundleIdentifier() -> String?

    /// Name and bundle identifier sampled from the same frontmost application.
    func frontmostApplication() -> (name: String?, bundleIdentifier: String?)
}

extension ClipboardSource {
    /// Sources without a picture-flavour probe remain usable.
    public func hasPicture() -> Bool { false }

    /// Sources without RTF remain usable.
    public func rtf() -> Data? { nil }

    /// Sources without application provenance remain usable; unknown apps are never excluded.
    public func frontmostApplicationBundleIdentifier() -> String? { nil }

    /// Combines the best-effort provenance fields for sources that do not provide an atomic sample.
    public func frontmostApplication() -> (name: String?, bundleIdentifier: String?) {
        (frontmostApplicationName(), frontmostApplicationBundleIdentifier())
    }
}
