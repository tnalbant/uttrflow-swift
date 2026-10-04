/// The table every destination is read from; a new app is a new row here and nowhere else.
public enum DestinationRules {
    /// DataGrip also matches JetBrains' broad code-editor prefix; the classifier chooses its longer SQL prefix.
    public static let standard: [DestinationRule] = [
        DestinationRule(
            bundlePrefixes: [
                "at.eggerapps.Postico", "com.tinyapp.TablePlus", "com.jetbrains.datagrip",
                "org.jkiss.dbeaver", "org.pgadmin.pgadmin4", "com.sequelpro", "com.sequel-ace",
            ],
            titleContains: ["pgAdmin", "pgAdmin 4"],
            nameWords: ["tableplus", "postico", "datagrip", "dbeaver", "pgadmin", "sequel"],
            kind: .sqlEditor
        ),
        DestinationRule(
            bundlePrefixes: ["com.apple.iWork.Numbers", "com.microsoft.Excel"],
            titleContains: ["Google Sheets"],
            nameWords: ["numbers", "excel"],
            kind: .spreadsheet
        ),
        DestinationRule(
            bundlePrefixes: [
                "com.microsoft.Word", "com.apple.iWork.Pages", "com.apple.TextEdit",
            ],
            titleContains: ["Google Docs"],
            nameWords: ["textedit", "pages", "word"],
            kind: .documentEditor
        ),
        DestinationRule(
            bundlePrefixes: ["com.apple.Notes", "notion.id", "md.obsidian", "net.shinyfrog.bear"],
            nameWords: ["notes", "notion", "obsidian", "bear", "craft", "drafts"],
            kind: .notes
        ),
        DestinationRule(
            bundlePrefixes: ["com.apple.reminders", "com.apple.ical"],
            destination: .document, terminalStop: .never
        ),
        DestinationRule(
            bundlePrefixes: [
                "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp",
                "net.kovidgoyal.kitty", "org.alacritty", "com.mitchellh.ghostty",
                "com.github.wez.wezterm", "co.zeit.hyper", "org.tabby",
            ],
            nameWords: [
                "terminal", "iterm", "iterm2", "warp", "kitty", "alacritty", "ghostty", "wezterm",
                "tabby",
            ],
            kind: .terminal
        ),
        DestinationRule(
            bundlePrefixes: [
                "com.apple.dt.Xcode", "com.todesktop.230313mzl4w4u92", "com.microsoft.VSCode",
                "dev.zed.Zed", "com.jetbrains.intellij", "com.jetbrains.pycharm",
                "com.jetbrains.goland", "com.jetbrains.rider", "com.jetbrains.webstorm",
                "com.jetbrains.phpstorm", "com.jetbrains.rubymine", "com.jetbrains.clion",
                "com.jetbrains.datagrip", "com.jetbrains.appcode", "com.jetbrains.mps",
                "com.sublimetext", "com.panic.Nova",
                "com.visualstudio.code", "org.vim.MacVim",
            ],
            nameWords: [
                "xcode", "code", "zed", "sublime", "cursor", "nova", "intellij", "pycharm", "goland",
                "vim", "neovim", "emacs",
            ],
            kind: .codeEditor
        ),
        DestinationRule(
            bundlePrefixes: [
                "com.tinyspeck.slackmacgap", "net.whatsapp", "desktop.whatsapp", "ru.keepcoder.Telegram",
                "org.telegram", "com.hnc.Discord", "com.apple.MobileSMS", "com.microsoft.teams",
                "org.whispersystems.signal",
            ],
            titleContains: [
                "Slack", "Discord", "Messages", "WhatsApp", "Telegram", "Telegram Web", "Teams",
                "Microsoft Teams", "Signal",
            ],
            nameWords: [
                "slack", "discord", "messages", "whatsapp", "telegram", "teams", "signal",
            ],
            kind: .chat
        ),
        DestinationRule(
            bundlePrefixes: [
                "com.apple.mail", "com.microsoft.Outlook", "com.superhuman", "com.readdle.smartemail",
            ],
            titleContains: ["Gmail", "Mail", "Outlook", "Spark", "Superhuman"],
            nameWords: ["mail", "outlook", "spark", "superhuman"],
            kind: .email
        ),
    ]

    /// The Chromium browsers, named here with every other app, for the reads that treat their engine differently.
    public static let chromiumBrowsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "org.chromium.Chromium", "com.microsoft.edgemac", "com.microsoft.edgemac.Beta",
        "com.microsoft.edgemac.Dev", "com.microsoft.edgemac.Canary", "com.brave.Browser",
        "com.brave.Browser.beta", "com.brave.Browser.nightly", "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera", "company.thebrowser.Browser",
    ]

    /// Every bundle prefix the rows of these kinds name, lowercased, for a module that asks only by identifier.
    public static func bundlePrefixes(of kinds: Set<AppKind>) -> [String] {
        standard.filter { $0.kind.map(kinds.contains) ?? false }
            .flatMap(\.bundlePrefixes).map { $0.lowercased() }
    }
}
