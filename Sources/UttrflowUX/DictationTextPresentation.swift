import Foundation
import UttrflowClipboard

/// A dictation's display form and clipboard handling decision, using the clipboard's secret rules.
public struct DictationTextPresentation: Sendable, Equatable {
    /// The words retained for copying or inserting.
    public let text: String
    /// Whether the text is a credential that must be hidden and written as concealed.
    public let isSecret: Bool

    /// Detects secrets once so every dictation surface shares one classification.
    public init(_ text: String) {
        self.text = text
        isSecret = ClipKindDetector.kind(of: text) == .secret
    }

    /// The text a dictation surface may show.
    public var displayText: String { isSecret ? PanelPresenter.mask : text }
}
