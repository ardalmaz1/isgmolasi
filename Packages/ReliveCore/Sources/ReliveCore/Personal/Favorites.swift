import Foundation

/// What can be a favorite.
public enum FavoriteKind: String, Codable, CaseIterable, Hashable, Sendable {
    /// One photo (a memory), by its photo-library identifier.
    case memory
    /// A moment, by its id. Independent of its photos' favorites.
    case moment
    /// Something made with Relive (a collage, story or book), by its id.
    case creation
}

/// One favorite: "this matters to us". Private and local; never written to the photo library
/// (it is not the Photos app's favorite flag) and never changes the story.
public struct FavoriteRecord: Codable, Hashable, Sendable {
    public var kind: FavoriteKind
    public var identifier: String
    public var favoritedAt: Date

    public init(kind: FavoriteKind, identifier: String, favoritedAt: Date) {
        self.kind = kind
        self.identifier = identifier
        self.favoritedAt = favoritedAt
    }
}

/// The couple's favorites. A favorite whose memory, moment or creation isn't there right now
/// (e.g. after Start Over) stays dormant and comes back with it.
public struct FavoriteCollection: Hashable, Sendable {
    private struct Key: Hashable, Sendable {
        var kind: FavoriteKind
        var identifier: String
    }

    private var favoritedAt: [Key: Date] = [:]

    public init(_ records: [FavoriteRecord] = []) {
        for record in records {
            let key = Key(kind: record.kind, identifier: record.identifier)
            // Keep the earliest date if a record appears twice.
            favoritedAt[key] = min(favoritedAt[key] ?? record.favoritedAt, record.favoritedAt)
        }
    }

    public func contains(_ kind: FavoriteKind, _ identifier: String) -> Bool {
        favoritedAt[Key(kind: kind, identifier: identifier)] != nil
    }

    /// Adds or removes a favorite. Returns whether anything changed.
    @discardableResult
    public mutating func set(_ kind: FavoriteKind, _ identifier: String, isFavorite: Bool, at date: Date) -> Bool {
        let key = Key(kind: kind, identifier: identifier)
        switch (isFavorite, favoritedAt[key] != nil) {
        case (true, false):
            favoritedAt[key] = date
            return true
        case (false, true):
            favoritedAt[key] = nil
            return true
        default:
            return false
        }
    }

    public func identifiers(_ kind: FavoriteKind) -> Set<String> {
        Set(favoritedAt.keys.filter { $0.kind == kind }.map(\.identifier))
    }

    public var memoryIDs: Set<AssetID> { identifiers(.memory) }
    public var momentIDs: Set<MomentID> { Set(identifiers(.moment).compactMap(UUID.init(uuidString:))) }
    public var creationIDs: Set<UUID> { Set(identifiers(.creation).compactMap(UUID.init(uuidString:))) }

    public var count: Int { favoritedAt.count }

    public func favoritedAt(_ kind: FavoriteKind, _ identifier: String) -> Date? {
        favoritedAt[Key(kind: kind, identifier: identifier)]
    }

    /// Every favorite, most recently favorited first (ties by kind and identifier) — a stable
    /// order for storage and tests.
    public var records: [FavoriteRecord] {
        favoritedAt.map { FavoriteRecord(kind: $0.key.kind, identifier: $0.key.identifier, favoritedAt: $0.value) }
            .sorted { lhs, rhs in
                if lhs.favoritedAt != rhs.favoritedAt { return lhs.favoritedAt > rhs.favoritedAt }
                if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
                return lhs.identifier < rhs.identifier
            }
    }
}
