import Foundation
import SwiftData

// SwiftData schema for Prototype 0.1.
//
// Two kinds of data live here:
// - User-authored data (profile, notes, hidden moments, cover choices) is modelled explicitly,
//   one record per item, because it is irreplaceable.
// - Derived data (asset metadata + analysis, the generated story) is stored as versioned JSON
//   snapshots of ReliveCore value types. It can always be rebuilt from the photo library, and
//   keeping it as documents keeps the engine free of persistence concerns.
//
// Every property has a default value and there are no unique constraints, which keeps the
// schema compatible with CloudKit-backed SwiftData should sync be added later.

@Model
final class StoredProfile {
    var partnerName: String = ""
    var userName: String?
    var relationshipStart: Date?
    var relationshipStartPrecision: String?
    var onboardingStartedAt: Date?
    var storyRevealedAt: Date?
    var smileResponse: String?
    var smileRespondedAt: Date?
    var momentsOpenedCount: Int = 0
    var lastViewedMomentID: UUID?
    var foundMomentID: UUID?
    var foundAssetID: String?
    var foundOnDay: Date?

    init() {}
}

/// One selected photo or video: a reference to the library plus cached metadata/analysis.
@Model
final class StoredAsset {
    var localIdentifier: String = ""
    /// JSON-encoded `MemoryAsset` (including analysis).
    var payload: Data = Data()
    var selectedAt: Date = Date()

    init(localIdentifier: String, payload: Data, selectedAt: Date) {
        self.localIdentifier = localIdentifier
        self.payload = payload
        self.selectedAt = selectedAt
    }
}

/// The most recently generated story.
@Model
final class StoredStorySnapshot {
    var version: Int = 0
    /// JSON-encoded `Story`.
    var payload: Data = Data()
    var generatedAt: Date = Date()

    init(version: Int, payload: Data, generatedAt: Date) {
        self.version = version
        self.payload = payload
        self.generatedAt = generatedAt
    }
}

/// What the user decided about one moment.
@Model
final class StoredMomentState {
    var momentID: UUID = UUID()
    var note: String?
    var noteUpdatedAt: Date?
    var isHidden: Bool = false
    var isExcludedFromSurfacing: Bool = false
    var heroOverrideAssetID: String?
    var lastSurfacedAt: Date?
    var surfacedCount: Int = 0
    var lastOpenedAt: Date?

    init(momentID: UUID) {
        self.momentID = momentID
    }
}

enum PersistenceSchema {
    static let models: [any PersistentModel.Type] = [
        StoredProfile.self,
        StoredAsset.self,
        StoredStorySnapshot.self,
        StoredMomentState.self,
    ]
}
