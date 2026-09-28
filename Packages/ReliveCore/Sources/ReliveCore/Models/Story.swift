import Foundation

/// The generated relationship story: chapters and moments, chronological.
///
/// A Story is a derived artifact — it can always be rebuilt from the selected assets. User-owned
/// data (notes, hidden moments, cover choices) is stored separately in `MomentUserState`.
public struct Story: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var generatedAt: Date
    /// Chronological, undated moments last.
    public var moments: [Moment]
    public var chapters: [Chapter]

    public init(version: Int = Story.currentVersion, generatedAt: Date, moments: [Moment], chapters: [Chapter]) {
        self.version = version
        self.generatedAt = generatedAt
        self.moments = moments
        self.chapters = chapters
    }

    public static let empty = Story(generatedAt: .distantPast, moments: [], chapters: [])

    public var isEmpty: Bool { moments.isEmpty }

    public func moment(id: MomentID) -> Moment? {
        moments.first { $0.id == id }
    }

    public func chapter(id: UUID) -> Chapter? {
        chapters.first { $0.id == id }
    }

    public func chapter(for moment: Moment) -> Chapter? {
        moment.chapterID.flatMap(chapter(id:))
    }

    /// Every asset referenced by the story.
    public var allAssetIDs: Set<AssetID> {
        Set(moments.flatMap(\.assetIDs))
    }
}
