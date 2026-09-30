import AppIntents

@MainActor
enum DictationIntentBridge {
    static var toggle: @MainActor () async -> Void = {}
}

struct ToggleDictationIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Dictation"
    static let description = IntentDescription("Start or stop dictation in Uttrflow.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        await DictationIntentBridge.toggle()
        return .result()
    }
}

struct UttrflowAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleDictationIntent(),
            phrases: ["Toggle dictation in \(.applicationName)"],
            shortTitle: "Toggle Dictation",
            systemImageName: "mic")
    }
}
