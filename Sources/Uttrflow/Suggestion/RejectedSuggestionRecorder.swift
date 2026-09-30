import Foundation
import OSLog
import UttrflowContext
import UttrflowPredictStore

protocol RejectedSuggestionStore: Sendable {
    func recordRejected(_ text: String, in surface: Surface) async throws
}

extension PredictStore: RejectedSuggestionStore {}

/// Records rejected suggestions, retries failed writes and suppresses uncertain lines for this session.
@MainActor
final class RejectedSuggestionRecorder {
    private static let log = Logger(subsystem: "com.uttrflow.Uttrflow", category: "predict")
    private static let limit = 32
    private let store: any RejectedSuggestionStore
    private var unwritten: [PendingRejection] = []
    private var suppressed: Set<RejectedSuggestion> = []
    private var nextID: UInt64 = 0
    private var isRetrying = false

    init(store: any RejectedSuggestionStore) {
        self.store = store
    }

    /// Records a rejection or holds it for retry, suppressing it when the write fails.
    func record(_ text: String, in surface: Surface) async {
        do {
            try await store.recordRejected(text, in: surface)
        } catch {
            let rejection = RejectedSuggestion(text: text, surface: surface)
            unwritten.append(PendingRejection(id: claimID(), rejection: rejection))
            if unwritten.count > Self.limit { unwritten.removeFirst() }
            suppressed.insert(rejection)
            Self.log.error(
                "A rejected suggestion's corpus write failed and is held for retry: \(failure(error), privacy: .public)"
            )
        }
    }

    /// Retries held rejection writes in order, stopping at the first repeated failure.
    func retry() async {
        guard !isRetrying else { return }
        isRetrying = true
        defer { isRetrying = false }
        while let pending = unwritten.first {
            do {
                try await store.recordRejected(pending.rejection.text, in: pending.rejection.surface)
                if unwritten.first?.id == pending.id { unwritten.removeFirst() }
                if !unwritten.contains(where: { $0.rejection == pending.rejection }) {
                    suppressed.remove(pending.rejection)
                }
            } catch {
                Self.log.error(
                    "A rejected suggestion's corpus retry failed: \(failure(error), privacy: .public)")
                return
            }
        }
    }

    /// Gives a held rejection a stable identity through actor reentrancy.
    private func claimID() -> UInt64 {
        defer { nextID &+= 1 }
        return nextID
    }

    /// Whether the failed write keeps this line unavailable in its surface this session.
    func suppresses(_ text: String, in surface: Surface) -> Bool {
        suppressed.contains(RejectedSuggestion(text: text, surface: surface))
    }

    /// Names the error type and case without logging a possible text payload.
    private func failure(_ error: any Error) -> String {
        let type = String(describing: Swift.type(of: error))
        let mirror = Mirror(reflecting: error)
        if mirror.displayStyle == .enum, let label = mirror.children.first?.label {
            return "\(type).\(label)"
        }
        let bridged = error as NSError
        return "\(type) domain=\(bridged.domain) code=\(bridged.code)"
    }
}

private struct RejectedSuggestion: Hashable {
    let text: String
    let surface: Surface
}

private struct PendingRejection {
    let id: UInt64
    let rejection: RejectedSuggestion
}
