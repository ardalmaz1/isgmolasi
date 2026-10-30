import Foundation
import ReliveCore

/// One finished thing the couple made in Relive: a collage or story, or a Memory Book. Books
/// keep their own model and storage (`MemoryBook`); this only lists them side by side.
enum KeptItem: Identifiable, Hashable {
    case creation(SavedCreation)
    case book(MemoryBook)

    var id: UUID {
        switch self {
        case .creation(let creation): creation.id
        case .book(let book): book.id
        }
    }

    var updatedAt: Date {
        switch self {
        case .creation(let creation): creation.updatedAt
        case .book(let book): book.updatedAt
        }
    }

    var kind: KeptKind {
        switch self {
        case .creation(let creation):
            switch creation.kind {
            case .collage: .collage
            case .story: .story
            case .movie: .movie
            }
        case .book: .book
        }
    }

    /// Its key in the favorites list.
    var favoriteID: String { id.uuidString }
}

/// What kind of thing was made, for filters and labels.
enum KeptKind: String, CaseIterable, Hashable, Identifiable {
    case collage
    case story
    case book
    case movie

    var id: String { rawValue }

    /// "Collage", for "Collage · Edited 12 minutes ago".
    var name: String {
        switch self {
        case .collage: String(localized: "Collage")
        case .story: String(localized: "Story")
        case .book: String(localized: "Book")
        case .movie: String(localized: "Movie")
        }
    }

    var pluralName: String {
        switch self {
        case .collage: String(localized: "Collages")
        case .story: String(localized: "Stories")
        case .book: String(localized: "Books")
        case .movie: String(localized: "Movies")
        }
    }

    /// The neutral title used when the photos don't support a factual one.
    var neutralTitle: String {
        switch self {
        case .collage: String(localized: "Memory Collage")
        case .story: String(localized: "Memory Story")
        case .book: String(localized: "Memory Book")
        case .movie: String(localized: "Memory Movie")
        }
    }
}

extension StoryStore {
    /// Finished collages, stories and books, most recently changed first (ties by identifier,
    /// so the order never shuffles).
    var keptItems: [KeptItem] {
        let items = savedCreations.map(KeptItem.creation) + books.map(KeptItem.book)
        return items.sorted { lhs, rhs in
            lhs.updatedAt != rhs.updatedAt ? lhs.updatedAt > rhs.updatedAt : lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Finished creations the couple favorited.
    var favoriteKeptItems: [KeptItem] {
        keptItems.filter { isFavorite(.creation, $0.favoriteID) }
    }

    /// Deletes a collage, story or book from Relive. Its photos stay, in Relive and in Photos.
    func deleteKept(_ item: KeptItem) {
        switch item {
        case .creation(let creation): deleteCreation(id: creation.id)
        case .book(let book): deleteBook(id: book.id)
        }
    }
}
