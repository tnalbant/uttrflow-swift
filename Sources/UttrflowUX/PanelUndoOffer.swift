// Tracks which delete the panel's undo offer describes, so an older delete finishing late cannot claim it.
public import UttrflowClipboard

/// The one delete that can be undone, and a count of deletes so a late one can tell it was superseded.
public struct PanelUndoOffer: Sendable, Equatable {
    /// The clip the undo offer restores, or nil when there is nothing to undo.
    public private(set) var clip: Clip?
    /// How many deletes have been offered; each delete's ticket is the value it saw.
    public private(set) var deletes = 0
    /// The store operation that must finish before the current offer can be restored.
    public private(set) var pendingDelete: Task<Result<Void, ClipboardStoreError>, Never>?

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.clip == rhs.clip && lhs.deletes == rhs.deletes
    }

    /// An empty offer.
    public init() {}

    /// Offers `clip` as the undo for a delete starting now and returns that delete's ticket.
    public mutating func offer(_ clip: Clip?) -> Int {
        deletes += 1
        self.clip = clip
        pendingDelete = nil
        return deletes
    }

    /// Associates the delete operation with its offer while allowing undo to wait for it.
    public mutating func trackDelete(
        _ task: Task<Result<Void, ClipboardStoreError>, Never>, ticket: Int
    ) {
        guard isLatest(ticket) else { return }
        pendingDelete = task
    }

    /// Claims the current clip and its delete task so only this request can restore it.
    public mutating func claimForRestore() -> PanelUndoClaim? {
        guard let clip else { return nil }
        let pendingDelete = pendingDelete
        withdraw()
        return PanelUndoClaim(clip: clip, pendingDelete: pendingDelete)
    }

    /// Whether the delete holding `ticket` is still the one the offer describes.
    public func isLatest(_ ticket: Int) -> Bool { ticket == deletes }

    /// Withdraws the offer; a delete still in flight is superseded by it.
    public mutating func withdraw() {
        deletes += 1
        clip = nil
        pendingDelete = nil
    }
}

/// A claimed undo whose clip must wait for its delete to finish before restoration.
public struct PanelUndoClaim: Sendable {
    /// The clip this claim restores.
    public let clip: Clip
    fileprivate let pendingDelete: Task<Result<Void, ClipboardStoreError>, Never>?

    /// Waits for the delete tied to this clip and preserves its write error.
    public func waitForDelete() async throws(ClipboardStoreError) {
        guard let pendingDelete else { return }
        switch await pendingDelete.value {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }
}

/// Withdraws the undo offer before awaiting picture cleanup.
@MainActor
public enum PanelUndoExpiry {
    /// Runs the offer withdrawal synchronously before releasing held pictures.
    public static func expire(withdraw: () -> Void, releasingPictures: () async -> Void) async {
        withdraw()
        await releasingPictures()
    }
}
