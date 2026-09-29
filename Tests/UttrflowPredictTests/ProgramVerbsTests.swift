import Foundation
import Testing

@testable import UttrflowPredict

@Suite("Reading the verbs a program takes")
struct ProgramVerbsTests {
    @Test("A Makefile's targets are its rule heads, without variables, recipes, special targets or patterns.")
    func makefileTargets() {
        let makefile = """
            SWIFT := xcrun swift
            .PHONY: verify build
            verify: lint test
            \t$(SWIFT) test
            build test:
            \t@echo building
            %.o: %.c
            $(TARGET): build
            # release: not yet
            """
        #expect(MakefileTargets.names(in: makefile) == ["verify", "build", "test"])
    }

    @Test(
        "A justfile's recipes are its public recipe heads and aliases, without settings, variables or modules."
    )
    func justfileRecipes() {
        let justfile = """
            set shell := ["zsh", "-cu"]
            export PATH := "bin:" + env_var('PATH')
            version := "1.0"
            import 'common.just'
            mod deploy

            # Runs every check.
            verify: lint test
            \tswift test

            @lint:
            \tswiftlint

            test filter="": build
            \tswift test --filter {{filter}}

            serve addr="127.0.0.1:8080" *args:
            \t./serve {{addr}} {{args}}

            [private]
            helper:
            \techo hidden

            _setup:
            \techo hidden too

            [group('release')]
            build-app:
            \techo building

            alias b := build-app

            [group('private')]
            docs:
            \techo public

            [no-cd, private]
            clean:
            \techo hidden as well
            """
        #expect(
            JustfileRecipes.names(in: justfile) == [
                "verify", "lint", "test", "serve", "build-app", "b", "docs",
            ])
        #expect(JustfileRecipes.names(in: "") == [])
    }

    /// `just` and `make` each read their own file, so a project with both offers each only its own verbs.
    @Test("just reads the justfile and make the Makefile, in a project with one or both")
    func justAndMakeReadTheirOwnFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "verbs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let reader = SystemEnvironmentReader()

        try Data("verify-just:\n\techo just\n".utf8).write(to: directory.appending(path: "justfile"))
        #expect(await reader.values(of: .subcommand(of: "just"), in: directory.path) == ["verify-just"])
        #expect(await reader.values(of: .subcommand(of: "make"), in: directory.path) == nil)

        try Data("verify-make:\n\techo make\n".utf8).write(to: directory.appending(path: "Makefile"))
        #expect(await reader.values(of: .subcommand(of: "just"), in: directory.path) == ["verify-just"])
        #expect(await reader.values(of: .subcommand(of: "make"), in: directory.path) == ["verify-make"])
    }

    @Test("A manifest's scripts are the keys of its scripts object, whatever their commands hold.")
    func packageScripts() {
        let manifest = """
            {
              "name": "app",
              "scripts": {
                "dev": "vite",
                "build": "tsc && vite build",
                "test:unit": "vitest run --reporter=\\"dot, verbose\\"",
                "lint": "eslint ."
              },
              "dependencies": { "vite": "^5" }
            }
            """
        #expect(PackageScripts.names(in: manifest) == ["build", "dev", "lint", "test:unit"])
        #expect(PackageScripts.names(in: "{ \"name\": \"app\" }") == [])
        #expect(PackageScripts.names(in: "scripts: dev") == nil)
    }

    @Test(
        "A help page's commands are its indented names, set off from their descriptions or listed with commas."
    )
    func helpCommands() {
        let docker = """
            Usage:  docker [OPTIONS] COMMAND

            Common Commands:
              run         Create and run a new container from an image
              exec        Execute a command in a running container
              ps          List containers

            Global Options:
                  --config string      Location of client config files
              -D, --debug              Enable debug mode
            """
        #expect(HelpCommands.names(in: docker) == ["run", "exec", "ps"])
        let gh =
            "CORE COMMANDS\n  auth:          Authenticate gh and git with GitHub\n  pr:            Manage pull requests\n"
        #expect(HelpCommands.names(in: gh) == ["auth", "pr"])
        let cargo =
            "Installed Commands:\n    add                  Add dependencies\n    audit\n    b                    alias: build\n"
        #expect(HelpCommands.names(in: cargo) == ["add", "audit", "b"])
        let npm = "All commands:\n\n    access, adduser, audit, bugs,\n    completion, config\n"
        #expect(
            HelpCommands.names(in: npm) == ["access", "adduser", "audit", "bugs", "completion", "config"])
        #expect(HelpCommands.names(in: "--cache\ncommands\ninstall\n") == ["commands", "install"])
        #expect(HelpCommands.names(in: "Usage: swift [options] file\n  Compiles the file given.\n").isEmpty)
        #expect(HelpCommands.names(in: "  this is ordinary indented prose\n").isEmpty)
        #expect(
            HelpCommands.names(in: "  build2\tBuilds the project\n  test3\tRuns the tests\n")
                == ["build2", "test3"])
    }
}

/// A directory of that many empty, executable files, named `<prefix><n>`, removed when the caller is done with it.
private func executableDirectory(count: Int, prefix: String) throws -> String {
    let root = FileManager.default.temporaryDirectory.appending(path: "path-\(UUID().uuidString)")
        .path(percentEncoded: false)
    try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    for index in 0..<count {
        let path = "\(root)/\(prefix)\(index)"
        FileManager.default.createFile(atPath: path, contents: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    }
    return root
}

/// Runs `body` with `PATH` set to `path`, restoring whatever `PATH` named before.
private func withPath(_ path: String, _ body: () async -> Void) async {
    let original = ProcessInfo.processInfo.environment["PATH"] ?? ""
    setenv("PATH", path, 1)
    defer { setenv("PATH", original, 1) }
    await body()
}

// Serialized because every test here mutates the process-wide `PATH`, which a parallel run would race on.
@Suite("Reading programs off PATH", .serialized)
struct ExecutableSearchTests {
    @Test("One PATH directory holding more executables than the cap is not read past it.")
    func capAppliesWithinOneDirectory() async throws {
        let overflowing = try executableDirectory(
            count: SystemEnvironmentReader.executableLimit + 1, prefix: "over-")
        defer { try? FileManager.default.removeItem(atPath: overflowing) }
        await withPath(overflowing) {
            let names = await SystemEnvironmentReader().values(of: .executable, in: "/")
            #expect(names?.count == SystemEnvironmentReader.executableLimit)
        }
    }

    @Test("The cap is shared across every PATH directory, in PATH's own order.")
    func capIsSharedAcrossDirectories() async throws {
        let first = try executableDirectory(count: SystemEnvironmentReader.executableLimit, prefix: "a-")
        defer { try? FileManager.default.removeItem(atPath: first) }
        let second = try executableDirectory(count: 5, prefix: "b-")
        defer { try? FileManager.default.removeItem(atPath: second) }
        await withPath("\(first):\(second)") {
            let names = await SystemEnvironmentReader().values(of: .executable, in: "/")
            #expect(names?.count == SystemEnvironmentReader.executableLimit)
            #expect(names?.contains { $0.hasPrefix("b-") } == false)
        }
    }
}
