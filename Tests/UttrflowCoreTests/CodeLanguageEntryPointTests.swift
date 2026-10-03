// Tests for the file-name and caret-fragment entry points of the language detector.

import Testing

@testable import UttrflowCore

@Suite("Language from a file name")
struct CodeLanguageFileNameTests {
    @Test(
        "every listed extension names its language",
        arguments: [
            ("a.swift", CodeLanguage.swift), ("a.py", .python), ("a.pyw", .python), ("a.pyi", .python),
            ("a.rb", .ruby), ("Rakefile.rake", .ruby), ("x.gemspec", .ruby),
            ("a.js", .javascript), ("a.mjs", .javascript), ("a.cjs", .javascript), ("a.jsx", .javascript),
            ("a.ts", .typescript), ("a.tsx", .typescript), ("a.mts", .typescript), ("a.cts", .typescript),
            ("a.json", .json), ("a.geojson", .json), ("a.sql", .sql),
            ("a.sh", .shell), ("a.bash", .shell), ("a.zsh", .shell), ("a.ksh", .shell),
            ("a.command", .shell), ("a.html", .html), ("a.htm", .html), ("a.xhtml", .html),
            ("a.css", .css), ("a.go", .go), ("a.rs", .rust), ("a.java", .java),
        ])
    func mapsExtension(_ each: (String, CodeLanguage)) {
        #expect(CodeLanguage.from(fileName: each.0) == each.1)
    }

    @Test("reads the last path component and ignores case")
    func pathAndCase() {
        #expect(CodeLanguage.from(fileName: "Sources/app.v2/Main.SWIFT") == .swift)
        #expect(CodeLanguage.from(fileName: "/tmp/build.dir/run") == nil)
    }

    @Test(
        "a name without a known extension answers with nothing",
        arguments: ["Makefile", ".bashrc", "notes.txt", "photo.png", "a.c", "a.", "", "a.yaml"])
    func refusesUnknown(_ name: String) {
        #expect(CodeLanguage.from(fileName: name) == nil)
    }
}

@Suite("Language from the text before a caret")
struct CodeLanguageFragmentTests {
    @Test("a short fragment is judged exactly like a clip")
    func shortFragmentMatchesClip() {
        let text = "def total(items):\n    if not items:\n        return None\n    return sum(items)\n"
        #expect(CodeLanguage.detect(fragment: text) == CodeLanguage.detect(text))
        #expect(CodeLanguage.detect(fragment: text) == .python)
    }

    @Test("only the end of a long fragment is read")
    func readsTheTail() {
        let swift = "guard let value else { return }\nlet name: String = \"\\(value)\"\n"
        let python = String(repeating: "def f(x):\n    return x\n", count: 40)
        #expect(CodeLanguage.detect(fragment: python + swift) == .swift)
    }

    @Test("the line the window cuts through is not read")
    func dropsTheCutLine() {
        // The window starts mid-line, so the Swift that line ends with is a half the detector never sees whole.
        let cutLine = String(repeating: "x", count: 250) + " guard a else { }; func f() -> Int { nil }\n"
        let fragment = String(repeating: "y", count: 40) + cutLine + "plain words here"
        #expect(CodeLanguage.detect(String(fragment.suffix(300))) == .swift)
        #expect(CodeLanguage.detect(fragment: fragment) == nil)
    }

    @Test(
        "prose and other formats before a caret answer with nothing",
        arguments: [
            "Select all the files from the folder and delete them.",
            "I went to the shop; it was closed; I came home.",
            "I told them {name} would be there, and it was.",
            "- one\n- two\n\nSome **bold** text.",
            "name: build\non:\n  push:\n    branches: [main]",
            "import Foundation",
            "x = 1",
        ])
    func refuses(_ text: String) {
        #expect(CodeLanguage.detect(fragment: text) == nil)
    }
}
