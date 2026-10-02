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
