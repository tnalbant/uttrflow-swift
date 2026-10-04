import Testing

@testable import UttrflowCore

/// Regression for issue 217: a window-title fragment has to stand as words before it picks a formatter.
@Suite("A title substring decides nothing mid-word", .bug(id: 217))
struct TitleFragmentWordBoundaryTests {
    @Test("refuses a fragment buried inside a longer word")
    func refusesAMidWordFragment() {
        let rule = DestinationRule(titleContains: ["Gmail"], destination: .email)
        #expect(!rule.matchesTitle(AppContext(documentName: "gmailer release notes")))
        #expect(!rule.matchesTitle(AppContext(documentName: "ungmail")))
        #expect(rule.matchesTitle(AppContext(documentName: "Inbox (3) - Gmail")))
    }

    @Test("every browser tab the table is written for still reads off its title")
    func keepsTheTabsItWasWrittenFor() {
        for (title, expected) in [
            ("Quarterly plan - Google Docs", Destination.document),
            ("Budget - Google Sheets", .spreadsheet),
            ("Inbox (3) - Gmail", .email),
            ("pgAdmin 4", .sqlEditor),
        ] {
            let app = AppContext(bundleIdentifier: "com.google.Chrome", documentName: title)
            #expect(DestinationClassifier.classify(app) == expected)
        }
    }
}

/// Regression for issue 3363: a common noun in a page's subject does not make a browser tab a chat or email app.
@Suite("A title names a web app only at its edge", .bug(id: 3363))
struct TitleNamesWebAppAtEdgeTests {
    @Test("a page whose subject uses an app's name stays plain")
    func subjectWordsDecideNothing() {
        for title in [
            "Messages API reference", "Signal processing notes", "Spark plan",
            "Teams overview - Microsoft Learn",
            "Mail merge guide", "How to use Gmail filters - Help Center",
        ] {
            let app = AppContext(bundleIdentifier: "com.apple.Safari", documentName: title)
            #expect(DestinationClassifier.classify(app) == .plain, "\(title)")
        }
    }

    @Test("a hosted app's own name at either end of the title still decides")
    func edgeNamesDecide() {
        for (title, expected) in [
            ("general (Channel) - Example Workspace - Slack", Destination.messaging),
            ("Discord | #general | Example Server", .messaging),
            ("(3) WhatsApp", .messaging),
            ("Chat | Microsoft Teams", .messaging),
            ("Inbox (12) — Mail", .email),
            ("Inbox - me@example.com - Outlook", .email),
        ] {
            let app = AppContext(bundleIdentifier: "com.apple.Safari", documentName: title)
            #expect(DestinationClassifier.classify(app) == expected, "\(title)")
        }
    }
}
