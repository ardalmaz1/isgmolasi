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
    public static let minimumPhotos = 4
    /// Keeps a book browsable and its memory use bounded; larger sources are sampled evenly.
    public static let maximumPhotos = 60
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
        includesMomentNotes: Bool = true
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

    /// A new book, or why there isn't enough to make one.
    public func makeBook(from source: CreationSource, id: UUID = UUID(), now: Date) -> Result<MemoryBook, CreationShortfall> {
        let photos = photos(for: source)
        guard photos.count >= BookLimits.minimumPhotos else {
            return .failure(.notEnoughPhotos(available: photos.count, required: BookLimits.minimumPhotos))
        }
        return .success(MemoryBook(id: id, createdAt: now, source: source, photoIDs: photos))
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
