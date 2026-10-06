import Foundation
import Testing

@testable import UttrflowAI
@testable import UttrflowCore

/// Whether an engine finishes with the network off; an exhaustive switch, so a new kind must decide.
private func runsWithoutNetwork(_ kind: TransformerKind) -> Bool {
    switch kind {
    case .foundationModels: true  // Apple's model, already on this Mac.
    case .localModel: true  // Open weights, already on disk.
    case .rules: true  // String arithmetic; it cannot reach anything.
    case .cloud: false  // The retired hosted engine, a network call.
    case .untidied: true  // Not an engine: what the record says when none of them ran.
    }
}

/// The assembly of engines refuses a network engine even when offered one. See Docs/offline.md.
@Suite("Offline guarantee")
struct OfflineGuaranteeTests {
    /// Whatever the build assembles must run on this Mac alone, even after an engine is added.
    @Test("every engine the shipping build assembles runs without the network")
    func assembledEnginesAreAllLocal() {
        for kind in TextTransformers.all().map(\.kind) {
            #expect(runsWithoutNetwork(kind), "\(kind.rawValue) needs the network to work")
        }
    }

    /// `route` is what the pipeline tries, so a preference reaching a network engine is caught here.
    @Test("the route the pipeline will take reaches no network engine")
    func shippingRouteIsLocal() {
        let route = TextTransformers.router(configuration: .default).route

        #expect(!route.isEmpty, "a route with nothing in it would dead-end every dictation")
        for kind in route {
            #expect(runsWithoutNetwork(kind), "the default route reaches \(kind.rawValue)")
        }
    }

    /// A stored preference, written by hand, can name an engine this binary lacks.
    @Test("a stored preference asking for the cloud is dropped, not honoured")
    func storedCloudPreferenceIsDropped() {
        let stored = EngineConfiguration(
            speech: .whisperKit, transformerPreference: [.cloud, .foundationModels, .rules]
        )

        #expect(!stored.resolvedTransformerPreference.contains(.cloud))
        for kind in stored.resolvedTransformerPreference {
            #expect(runsWithoutNetwork(kind), "a stored preference resolved to \(kind.rawValue)")
        }
    }

    /// A kind this build lets the user select must not need a connection.
    @Test("every kind this build lets the user select works offline")
    func selectableKindsAreLocal() {
        for kind in TransformerKind.selectable {
            #expect(runsWithoutNetwork(kind), "\(kind.rawValue) is selectable but needs the network")
        }
    }
}
