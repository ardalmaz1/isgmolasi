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
    // Today's Surprise Memory (v0.2). Optional, so existing stores migrate automatically.
    var surpriseMomentID: UUID?
    var surpriseAssetID: String?
    var surpriseOnDay: Date?
    var surpriseDismissed: Bool = false

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

/// An image Relive itself saved to the photo library (a collage or story card). Remembered so
/// that, with limited photo access — where new images Relive saves become visible to it — they
/// are never imported back into the story as memories.
@Model
final class StoredCreatedAsset {
    var localIdentifier: String = ""
    var createdAt: Date = Date()

    init(localIdentifier: String, createdAt: Date) {
        self.localIdentifier = localIdentifier
        self.createdAt = createdAt
    }
}

/// A Memory Book (v0.3): its definition as JSON — source, photo references, cover, style, note.
/// Never pixels; pages are laid out again from the story whenever the book opens.
@Model
final class StoredMemoryBook {
    var bookID: UUID = UUID()
    /// JSON-encoded `MemoryBook`.
    var payload: Data = Data()
    var updatedAt: Date = Date()

    init(bookID: UUID, payload: Data, updatedAt: Date) {
        self.bookID = bookID
        self.payload = payload
        self.updatedAt = updatedAt
    }
}

/// A favorite (v0.4): a memory, moment or creation the couple chose to keep close. Local only —
/// never the Photos app's favorite flag.
@Model
final class StoredFavorite {
    /// `FavoriteKind` raw value: "memory", "moment" or "creation".
    var kind: String = ""
    var identifier: String = ""
    var favoritedAt: Date = Date()

    init(kind: String, identifier: String, favoritedAt: Date) {
        self.kind = kind
        self.identifier = identifier
        self.favoritedAt = favoritedAt
    }
}

/// A collage or story kept in Relive (v0.4) — a draft or a finished creation — as JSON state.
/// Never pixels; it is drawn again from the user's photos whenever it is shown.
@Model
final class StoredCreation {
    var creationID: UUID = UUID()
    /// `SavedCreationKind` raw value.
    var kind: String = ""
    /// `SavedCreationStatus` raw value.
    var status: String = ""
    /// JSON-encoded `SavedCreation`.
    var payload: Data = Data()
    var updatedAt: Date = Date()

    init(creationID: UUID, kind: String, status: String, payload: Data, updatedAt: Date) {
        self.creationID = creationID
        self.kind = kind
        self.status = status
        self.payload = payload
        self.updatedAt = updatedAt
    }
}

enum PersistenceSchema {
    static let models: [any PersistentModel.Type] = [
        StoredProfile.self,
        StoredAsset.self,
        StoredStorySnapshot.self,
        StoredMomentState.self,
        StoredCreatedAsset.self,
        StoredMemoryBook.self,
        StoredFavorite.self,
        StoredCreation.self,
    ]
}
