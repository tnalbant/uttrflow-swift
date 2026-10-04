import Testing

@testable import UttrflowCore

@Suite("Whether the caret sits in a comment")
struct CodeCommentContextTests {
    @Test(
        "calls a line comment a comment",
        arguments: [
            ("Cache.swift", "// "), ("app.js", "  // note: "), ("main.go", "\t// TODO "),
            ("script.py", "# "), ("deploy.sh", "    # "), ("query.sql", "-- "),
        ])
    func lineCommentIsAComment(document: String, preceding: String) {
        #expect(CodeCommentContext.isComment(precedingText: preceding, documentName: document))
    }

    @Test(
        "calls executable code not a comment",
        arguments: [
            ("Cache.swift", "func read() -> Value {"), ("Cache.swift", "    "),
            ("app.js", "const total = "), ("query.sql", "SELECT * FROM "),
        ])
    func codeIsNotAComment(document: String, preceding: String) {
        #expect(!CodeCommentContext.isComment(precedingText: preceding, documentName: document))
    }

    @Test("calls a caret inside an unterminated block comment a comment")
    func openBlockCommentIsAComment() {
        #expect(
            CodeCommentContext.isComment(
                precedingText: "let x = 1\n/* still writing this ", documentName: "Cache.swift"))
    }

    @Test("does not call a caret after a closed block comment a comment")
    func closedBlockCommentIsNotAComment() {
        #expect(
            !CodeCommentContext.isComment(
                precedingText: "/* done */ let x = ", documentName: "Cache.swift"))
    }

    @Test("ignores block markers inside strings and line comments")
    func blockMarkersInsideStringsAndLineCommentsAreIgnored() {
        #expect(
            !CodeCommentContext.isComment(
                precedingText: "let s = \"/*\"\nlet y = ", documentName: "Cache.swift"))
        #expect(
            !CodeCommentContext.isComment(
                precedingText: "let glob = \"src/**/*.ts\"\nlet y = ", documentName: "Cache.swift"))
        #expect(
            !CodeCommentContext.isComment(
                precedingText: "// /*\nlet y = ", documentName: "Cache.swift"))
    }

    @Test("recognizes a block opener after a string that contains comment markers")
    func blockOpenerAfterStringIsAComment() {
        #expect(
            CodeCommentContext.isComment(
                precedingText: "let s = \"*/\"\n/* still writing this ", documentName: "Cache.swift"))
    }

    @Test(
        "calls a line comment after code on the caret's line a comment",
        arguments: [("main.swift", "let x = f() // "), ("main.py", "x = 1  # "), ("app.js", "a()\nb() // ")])
    func trailingCommentIsAComment(document: String, preceding: String) {
        #expect(CodeCommentContext.isComment(precedingText: preceding, documentName: document))
    }

    @Test(
        "does not call a line marker inside a string a comment",
        arguments: [
            ("main.swift", "let url = \"https://"),
            ("main.swift", "let url = \"https://x.test\"\nlet y = "),
        ])
    func markerInsideStringIsNotAComment(document: String, preceding: String) {
        #expect(!CodeCommentContext.isComment(precedingText: preceding, documentName: document))
    }

    @Test(
        "calls an open Python docstring a comment",
        arguments: [
            "def f():\n    \"\"\"", "def f():\n    '''Load ",
            "\"\"\"Module.\"\"\"\ndef f():\n    \"\"\"",
        ])
    func openDocstringIsAComment(preceding: String) {
        #expect(CodeCommentContext.isComment(precedingText: preceding, documentName: "main.py"))
    }

    @Test("does not call code after a closed docstring a comment")
    func closedDocstringIsNotAComment() {
        #expect(
            !CodeCommentContext.isComment(
                precedingText: "def f():\n    \"\"\"Load.\"\"\"\n    return ", documentName: "main.py"))
    }

    @Test("reads the extension off a window title that carries more than the filename")
    func readsExtensionFromAWindowTitle() {
        #expect(
            CodeCommentContext.isComment(precedingText: "// ", documentName: "Retrier.swift — Uttrflow"))
    }

    @Test(
        "never calls an unrecognised or missing document a comment",
        arguments: [(nil, "// "), ("notes.txt", "// "), ("Cache.swift", nil)] as [(String?, String?)])
    func unknownDocumentIsNeverAComment(document: String?, preceding: String?) {
        #expect(!CodeCommentContext.isComment(precedingText: preceding, documentName: document))
    }
}
