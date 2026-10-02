import CoreGraphics
import UttrflowCore

/// Reads whether a binding's key and modifiers are actually held, apart from any event a tap delivered. See `Docs/stuck-recording.md`.
protocol RealKeyStateReading: Sendable {
    func isDown(_ binding: HotkeyBinding) -> Bool
}

/// Asks the window server directly, the same way `CarbonHotkeyMonitor`'s poll does.
struct SystemKeyState: RealKeyStateReading {
    func isDown(_ binding: HotkeyBinding) -> Bool {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let modifiers = Set(HotkeyModifier.held(in: flags))
        let isFunctionDown = flags.contains(.maskSecondaryFn)
        if binding.isFunctionHold { return isFunctionDown }
        if binding.heldModifier != nil, binding.modifiers.isEmpty {
            guard let named = HotkeyBinding.modifier(ofKeyCode: binding.keyCode) else { return false }
            return modifiers == [named] && !isFunctionDown
        }
        if binding.heldModifier != nil { return modifiers == binding.modifiers }
        guard CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(binding.keyCode)) else {
            return false
        }
        return modifiers == binding.modifiers
    }
}
