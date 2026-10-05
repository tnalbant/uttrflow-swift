// The `fit` command: rebuilds a fitted artifact from its committed text-free table, with no audio and no network.
import ArgumentParser
private import Foundation
private import UttrflowEval

/// Reads a fit table, checks its schema, fits the linear scorer and prints the weights digest.
struct FitFromTable: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fit",
        abstract: "Reproduce a fitted scorer from a committed fit table and print its weights digest."
    )

    @Option(name: .customLong("from-table"), help: "The fit table to read.")
    var table: String

    @Option(name: .long, help: "The committed weights digest; exits 1 when the fit does not reproduce it.")
    var expect: String?

    func run() throws {
        let read = try FitTable.read(Data(contentsOf: URL(filePath: table)))
        let digest = read.fitLinearScorer().digest
        print(digest)
        if let expect, expect != digest {
            print("does not reproduce \(expect)")
            throw ExitCode.failure
        }
    }
}
