import UttrflowPredict

/// A deterministic history store with the same boundary as the app's prediction store.
struct FixturePredictionStore: PredictionStore {
    let candidates: [Candidate]

    func candidates(for surface: Surface, matching typed: String) async throws -> [Candidate] {
        candidates.filter { $0.text.hasPrefix(typed) }
    }
}

/// A deterministic machine reader seeded by one source fixture.
struct FixtureArbitrationMachine: EnvironmentReading {
    let answers: [EnvironmentKind: [String]]

    func values(of kind: EnvironmentKind, in directory: String, matching prefix: String) async -> [String]? {
        answers[kind]
    }
}
