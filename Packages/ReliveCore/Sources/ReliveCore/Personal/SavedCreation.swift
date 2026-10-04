import Foundation

/// What a saved creation is. Memory Books keep their own model (`MemoryBook`).
public enum SavedCreationKind: String, Codable, CaseIterable, Hashable, Sendable {
    case collage
    case story
}

/// A creation's place in its lifecycle. One record moves from draft to saved; it is never
/// copied, so there are no duplicates.
public enum SavedCreationStatus: String, Codable, Hashable, Sendable {
    /// Being made: kept automatically so work isn't lost. Shown under "Continue Editing".
    case draft
    /// Finished: the user saved it, or saved/shared its image. Shown in "My Creations".
    case saved
}

/// Everything needed to reopen a collage as it was: its photos in order, style, shape and the
/// caption lines the user chose. The caption's words are not stored: they are derived again from
/// the photos (see `CreationLibrary.facts`), so they can never drift from the truth.
public struct CollageState: Codable, Hashable, Sendable {
    public var photoIDs: [AssetID]
    public var style: CollageStyle
    public var aspectRatio: CreationAspectRatio
    public var showsTitle: Bool
    public var showsDate: Bool
    public var showsPlace: Bool

    public init(photoIDs: [AssetID], style: CollageStyle, aspectRatio: CreationAspectRatio, showsTitle: Bool = true, showsDate: Bool = true, showsPlace: Bool = true) {
        self.photoIDs = photoIDs
        self.style = style
        self.aspectRatio = aspectRatio
        self.showsTitle = showsTitle
        self.showsDate = showsDate
        self.showsPlace = showsPlace
    }
}

/// Everything needed to reopen a story as it was: its cards (order, layouts, photos, the
/// user's show/hide choices) and style.
public struct StoryState: Codable, Hashable, Sendable {
    public var design: StoryDesign

    public init(design: StoryDesign) {
        self.design = design
    }
}

/// A collage or story kept in Relive — a draft or a finished creation. Its *state*, never its
/// pixels: it is drawn again from the user's own photos whenever it is shown or exported.
public struct SavedCreation: Codable, Hashable, Sendable, Identifiable {
    public static let currentVersion = 1

    public var id: UUID
    public var version: Int
    public var kind: SavedCreationKind
    public var status: SavedCreationStatus
    public var createdAt: Date
    public var updatedAt: Date
    /// When it became a finished creation.
    public var savedAt: Date?
    /// When its image was last saved to Photos or shared.
    public var exportedAt: Date?
    /// What it was started from — a hint for its title, used only when every photo still
    /// belongs to it.
    public var source: CreationSource
    public var collage: CollageState?
    public var story: StoryState?
    /// Metadata of the creation's photos (identifier, date, location, size — never pixels or
    /// analysis), so it can still be described and drawn when a photo isn't in the story right
    /// now: one picked from the photo library, or after Start Over.
    public var assetSnapshots: [MemoryAsset]

    public init(
        id: UUID = UUID(),
        kind: SavedCreationKind,
        status: SavedCreationStatus = .draft,
        createdAt: Date,
        updatedAt: Date? = nil,
        source: CreationSource,
        collage: CollageState? = nil,
        story: StoryState? = nil,
        assetSnapshots: [MemoryAsset] = []
    ) {
        self.id = id
        self.version = Self.currentVersion
        self.kind = kind
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.source = source
        self.collage = collage
        self.story = story
        self.assetSnapshots = assetSnapshots
    }

    public var isDraft: Bool { status == .draft }

    /// The creation's photos, in order.
    public var photoIDs: [AssetID] {
        switch kind {
        case .collage: collage?.photoIDs ?? []
        case .story: story?.design.photoIDs ?? []
        }
    }

    /// The library to show this creation with: `base` (the story) plus snapshots of its photos
    /// that aren't in the story right now. Memories in the story keep their full metadata.
    public func creationLibrary(base: CreationLibrary) -> CreationLibrary {
        let used = Set(photoIDs)
        let snapshots = assetSnapshots.filter { used.contains($0.id) }
        return snapshots.isEmpty ? base : base.addingPhotoLibraryAssets(snapshots)
    }

    /// Photos that can't be shown now (deleted, or no longer shared with Relive).
    public func missingPhotos(in library: CreationLibrary) -> [AssetID] {
        photoIDs.filter { !library.isUsable($0) }
    }

    /// What the creation may print about itself — the same rule as every creation.
    public func facts(in library: CreationLibrary) -> CreationFacts {
        library.facts(for: source, photos: photoIDs.filter(library.isUsable))
    }

    /// Records metadata snapshots for the creation's photos from `library` (keeping earlier
    /// snapshots of photos the library no longer knows). Analysis is left out: it is large,
    /// and a creation's photos are already chosen.
    public mutating func captureSnapshots(from library: CreationLibrary) {
        let used = Set(photoIDs)
        var byID = Dictionary(assetSnapshots.filter { used.contains($0.id) }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for id in photoIDs {
            guard var asset = library.assets[id] else { continue }
            asset.analysis = nil
            byID[id] = asset
        }
        assetSnapshots = photoIDs.compactMap { byID[$0] }
    }

    // MARK: - Lifecycle

    /// The draft becomes a finished creation (the same record — no duplicate).
    public mutating func markSaved(at date: Date) {
        if status == .draft {
            status = .saved
            savedAt = date
        }
        updatedAt = date
    }

    /// Its image was saved to Photos or shared: it is finished.
    public mutating func markExported(at date: Date) {
        markSaved(at: date)
        exportedAt = date
    }
}
