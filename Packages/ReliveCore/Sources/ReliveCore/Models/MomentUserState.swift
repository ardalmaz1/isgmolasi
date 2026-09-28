import Foundation

/// Everything the user (not the algorithm) decided about a moment. Stored locally, keyed by
/// moment id, and carried over when the story is regenerated (see `MomentReconciler`).
public struct MomentUserState: Codable, Hashable, Sendable {
    public var note: String?
    public var noteUpdatedAt: Date?
    /// "Hide this memory": removed from the timeline, statistics and Found for You.
    public var isHidden: Bool
    /// "Don't show this again": stays in the timeline but is never resurfaced.
    public var isExcludedFromSurfacing: Bool
    /// The user's choice of cover photo. Always wins over the algorithm while the asset exists.
    public var heroOverrideAssetID: AssetID?
    public var lastSurfacedAt: Date?
    public var surfacedCount: Int
    public var lastOpenedAt: Date?

    public init(
        note: String? = nil,
        noteUpdatedAt: Date? = nil,
        isHidden: Bool = false,
        isExcludedFromSurfacing: Bool = false,
        heroOverrideAssetID: AssetID? = nil,
        lastSurfacedAt: Date? = nil,
        surfacedCount: Int = 0,
        lastOpenedAt: Date? = nil
    ) {
        self.note = note
        self.noteUpdatedAt = noteUpdatedAt
        self.isHidden = isHidden
        self.isExcludedFromSurfacing = isExcludedFromSurfacing
        self.heroOverrideAssetID = heroOverrideAssetID
        self.lastSurfacedAt = lastSurfacedAt
        self.surfacedCount = surfacedCount
        self.lastOpenedAt = lastOpenedAt
    }

    public var hasNote: Bool {
        guard let note else { return false }
        return !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True when nothing distinguishes this from a default state (safe to drop).
    public var isDefault: Bool { self == MomentUserState() }
}
