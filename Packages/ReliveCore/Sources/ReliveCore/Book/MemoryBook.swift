import Foundation

/// The three looks of a Memory Book. A style changes typography, spacing, image treatment and
/// page composition — never which photos, words or dates are in the book.
public enum BookStyle: String, CaseIterable, Codable, Hashable, Sendable {
    /// Cream paper, generous white space, framed photos.
    case classic
    /// Bright paper, large photographs (portraits bleed to the edge), big serif type.
    case editorial
    /// Dark pages, photos as film frames, typewriter captions.
    case film

    public var displayName: String {
        switch self {
        case .classic: "Classic"
        case .editorial: "Editorial"
        case .film: "Film"
        }
    }
}

/// How many photos a book works with.
public enum BookLimits {
    /// Fewer than this is not a book.
    public static let minimumPhotos = 6
    /// Keeps a book browsable (no hundreds of pages) and its memory use bounded; larger sources
    /// are sampled evenly.
    public static let maximumPhotos = 40
}

/// A saved Memory Book: the *definition* of the book, not its pages or pixels.
///
/// Pages are laid out again from this definition each time the book is opened (see
/// `BookLayoutEngine`), so a book follows the story — a deleted photo simply drops out — and
/// stores only references to the user's own photos.
public struct MemoryBook: Codable, Hashable, Sendable, Identifiable {
    public static let currentVersion = 1

    public var id: UUID
    public var version: Int
    public var createdAt: Date
    public var updatedAt: Date
    /// What the book was made from; used for its title and to refresh it later.
    public var source: CreationSource
    public var style: BookStyle
    /// The book's photos in reading order (chronological unless the user rearranged them).
    public var photoIDs: [AssetID]
    /// The user's choice of cover; the best photo when nil.
    public var coverAssetID: AssetID?
    /// The user's own words, printed on the page after the cover.
    public var note: String?
    /// Print the notes the user wrote on moments, after each moment's opening page.
    public var includesMomentNotes: Bool
    /// Metadata (never pixels) of the book's photos: their own dates, locations and sizes, so the
    /// book can describe and draw them when they aren't in the story right now — photos chosen
    /// straight from the photo library (v0.3.1), and since v0.4 every photo, so a book still
    /// opens after Start Over. Memories in the story always win over these snapshots.
    public var photoLibraryAssets: [MemoryAsset]

    public init(
        id: UUID = UUID(),
        version: Int = MemoryBook.currentVersion,
        createdAt: Date,
        updatedAt: Date? = nil,
        source: CreationSource,
        style: BookStyle = .classic,
        photoIDs: [AssetID],
        coverAssetID: AssetID? = nil,
        note: String? = nil,
        includesMomentNotes: Bool = true,
        photoLibraryAssets: [MemoryAsset] = []
    ) {
        self.id = id
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.source = source
        self.style = style
        self.photoIDs = photoIDs
        self.coverAssetID = coverAssetID
        self.note = note
        self.includesMomentNotes = includesMomentNotes
        self.photoLibraryAssets = photoLibraryAssets
    }

    private enum CodingKeys: String, CodingKey {
        case id, version, createdAt, updatedAt, source, style, photoIDs, coverAssetID, note, includesMomentNotes, photoLibraryAssets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        version = try container.decode(Int.self, forKey: .version)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        source = try container.decode(CreationSource.self, forKey: .source)
        style = try container.decode(BookStyle.self, forKey: .style)
        photoIDs = try container.decode([AssetID].self, forKey: .photoIDs)
        coverAssetID = try container.decodeIfPresent(AssetID.self, forKey: .coverAssetID)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        includesMomentNotes = try container.decodeIfPresent(Bool.self, forKey: .includesMomentNotes) ?? true
        // Books saved before v0.3.1 have no photo-library photos.
        photoLibraryAssets = try container.decodeIfPresent([MemoryAsset].self, forKey: .photoLibraryAssets) ?? []
    }

    /// The library to lay this book out with: `base` plus the book's photo-library photos.
    public func creationLibrary(base: CreationLibrary) -> CreationLibrary {
        photoLibraryAssets.isEmpty ? base : base.addingPhotoLibraryAssets(photoLibraryAssets)
    }

    /// Remembers metadata for photo-library photos in the book (call after adding them).
    public mutating func rememberPhotoLibraryAssets(_ assets: [MemoryAsset]) {
        let inBook = Set(photoIDs)
        for asset in assets where inBook.contains(asset.id) && !photoLibraryAssets.contains(where: { $0.id == asset.id }) {
            photoLibraryAssets.append(asset)
        }
    }

    /// Records metadata snapshots of every photo in the book from `library` (analysis left out),
    /// keeping earlier snapshots of photos the library no longer knows.
    public mutating func captureSnapshots(from library: CreationLibrary) {
        var byID = Dictionary(photoLibraryAssets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for id in photoIDs {
            guard var asset = library.assets[id] else { continue }
            asset.analysis = nil
            byID[id] = asset
        }
        photoLibraryAssets = photoIDs.compactMap { byID[$0] }
    }

    /// Forgets photo-library metadata for photos no longer in the book.
    mutating func pruneUnusedAssets() {
        let used = Set(photoIDs)
        photoLibraryAssets.removeAll { !used.contains($0.id) }
    }

    /// The trimmed note, or nil when there are no words.
    public var trimmedNote: String? {
        guard let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty else { return nil }
        return note
    }
}

/// Makes and refreshes books from the story.
public struct MemoryBookBuilder: Sendable {
    public var library: CreationLibrary

    public init(library: CreationLibrary) {
        self.library = library
    }

    /// The photos a book from `source` starts with: everything usable, or an even sample of the
    /// best when there are more than `BookLimits.maximumPhotos`. Chronological, except for
    /// chosen photos, which keep the order they were chosen in.
    public func photos(for source: CreationSource) -> [AssetID] {
        switch source {
        case .photos(let ids):
            return library.initialPhotos(for: source, limit: min(ids.count, BookLimits.maximumPhotos))
        default:
            return library.initialPhotos(for: source, limit: BookLimits.maximumPhotos)
                .sorted(by: library.chronologicalOrder)
        }
    }

    /// A new book, or why there isn't enough to make one. Photos picked from the photo library
    /// (present in `library`) are remembered by their metadata.
    public func makeBook(from source: CreationSource, id: UUID = UUID(), now: Date) -> Result<MemoryBook, CreationShortfall> {
        let photos = photos(for: source)
        guard photos.count >= BookLimits.minimumPhotos else {
            return .failure(.notEnoughPhotos(available: photos.count, required: BookLimits.minimumPhotos))
        }
        let fromLibrary = photos.filter(library.photoLibraryAssetIDs.contains).compactMap { library.assets[$0] }
        return .success(MemoryBook(id: id, createdAt: now, source: source, photoIDs: photos, photoLibraryAssets: fromLibrary))
    }

    /// Re-reads the source (new photos, deleted ones), keeping the user's style, note and cover.
    public func refreshed(_ book: MemoryBook, now: Date) -> MemoryBook {
        var updated = book
        let photos = photos(for: book.source)
        if photos.count >= BookLimits.minimumPhotos {
            updated.photoIDs = photos
        }
        if let cover = updated.coverAssetID, !updated.photoIDs.contains(cover) {
            updated.coverAssetID = nil
        }
        updated.pruneUnusedAssets()
        updated.updatedAt = now
        return updated
    }
}

// MARK: - Light editing

extension MemoryBook {
    /// Removes a photo, keeping at least `BookLimits.minimumPhotos`. Returns false if it can't.
    @discardableResult
    public mutating func removePhoto(_ id: AssetID) -> Bool {
        guard photoIDs.count > BookLimits.minimumPhotos, let index = photoIDs.firstIndex(of: id) else { return false }
        photoIDs.remove(at: index)
        if coverAssetID == id { coverAssetID = nil }
        pruneUnusedAssets()
        return true
    }

    /// Moves a photo earlier (negative) or later (positive) in the book.
    @discardableResult
    public mutating func movePhoto(_ id: AssetID, by offset: Int) -> Bool {
        guard let index = photoIDs.firstIndex(of: id) else { return false }
        let target = index + offset
        guard photoIDs.indices.contains(target), target != index else { return false }
        photoIDs.swapAt(index, target)
        return true
    }

    /// Puts `newID` where `oldID` was. A photo can't be in a book twice.
    @discardableResult
    public mutating func replacePhoto(_ oldID: AssetID, with newID: AssetID) -> Bool {
        guard let index = photoIDs.firstIndex(of: oldID), !photoIDs.contains(newID) else { return false }
        photoIDs[index] = newID
        if coverAssetID == oldID { coverAssetID = newID }
        pruneUnusedAssets()
        return true
    }

    /// After choosing photos again: photos still chosen keep their places, new ones join the end.
    @discardableResult
    public mutating func setPhotos(_ ids: [AssetID]) -> Bool {
        let chosen = Set(ids)
        var updated = photoIDs.filter { chosen.contains($0) }
        updated += ids.filter { !updated.contains($0) }
        updated = Array(updated.prefix(BookLimits.maximumPhotos))
        guard updated.count >= BookLimits.minimumPhotos else { return false }
        photoIDs = updated
        if let cover = coverAssetID, !photoIDs.contains(cover) { coverAssetID = nil }
        pruneUnusedAssets()
        return true
    }

    /// The cover must be one of the book's own photos; nil goes back to the best photo.
    @discardableResult
    public mutating func setCover(_ id: AssetID?) -> Bool {
        if let id, !photoIDs.contains(id) { return false }
        coverAssetID = id
        return true
    }

    public mutating func setNote(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        note = trimmed.isEmpty ? nil : trimmed
    }
}
