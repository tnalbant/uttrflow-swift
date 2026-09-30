import CoreFoundation
import UttrflowUX

/// Reads the user's Globe-key action from the preference macOS uses for Keyboard settings.
enum GlobeKeySettings {
    static var action: GlobeKeyAction {
        let value =
            CFPreferencesCopyAppValue(
                "AppleFnUsageType" as CFString, "com.apple.HIToolbox" as CFString) as? NSNumber
        return GlobeKeyAction(rawValue: value?.intValue)
    }
}
