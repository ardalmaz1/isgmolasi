import Foundation

/// Numbers shown on the reveal and Us screens. Every value is computed from the actual story;
/// hidden moments and unavailable photos are excluded.
public struct StoryStatistics: Equatable, Sendable {
    /// Distinct photos and videos (duplicate copies not counted).
    public var memoryCount: Int
    public var photoCount: Int
    public var videoCount: Int
    public var momentCount: Int
    public var chapterCount: Int
    /// Distinct places. Named places are counted by name; unnamed locations are grouped by distance.
    public var placeCount: Int
    public var firstMemoryDate: Date?
    public var lastMemoryDate: Date?

    public static let zero = StoryStatistics(
        memoryCount: 0, photoCount: 0, videoCount: 0, momentCount: 0, chapterCount: 0, placeCount: 0,
        firstMemoryDate: nil, lastMemoryDate: nil
    )

    public init(
        memoryCount: Int,
        photoCount: Int,
        videoCount: Int,
        momentCount: Int,
        chapterCount: Int,
        placeCount: Int,
        firstMemoryDate: Date?,
        lastMemoryDate: Date?
    ) {
        self.memoryCount = memoryCount
        self.photoCount = photoCount
        self.videoCount = videoCount
        self.momentCount = momentCount
        self.chapterCount = chapterCount
        self.placeCount = placeCount
        self.firstMemoryDate = firstMemoryDate
        self.lastMemoryDate = lastMemoryDate
    }

    /// - Parameters:
    ///   - isAvailable: whether an asset can still be shown (not deleted / access not revoked).
    ///   - unnamedPlaceRadius: unnamed locations closer than this count as one place.
    public static func compute(
        story: Story,
        assets: [AssetID: MemoryAsset],
        userStates: [MomentID: MomentUserState],
        isAvailable: (AssetID) -> Bool,
        unnamedPlaceRadius: Double = 10_000
    ) -> StoryStatistics {
        var photos = 0, videos = 0
        var moments = 0
        var chapters = Set<UUID>()
        var first: Date?, last: Date?
        var namedPlaces = Set<String>()
        var namedCoordinates: [GeoCoordinate] = []
        var unnamedCoordinates: [GeoCoordinate] = []

        for moment in story.moments where !(userStates[moment.id]?.isHidden ?? false) {
            let duplicates = Set(moment.duplicateAssetIDs)
            let available = moment.assetIDs.filter { isAvailable($0) && !duplicates.contains($0) }
            guard !available.isEmpty else { continue }
            moments += 1
            if let chapterID = moment.chapterID { chapters.insert(chapterID) }
            for id in available {
                if assets[id]?.kind == .video { videos += 1 } else { photos += 1 }
            }
            if let start = moment.startDate { first = min(first ?? start, start) }
            if let end = moment.endDate { last = max(last ?? end, end) }
            if let place = moment.place {
                namedPlaces.insert(place.comparisonKey)
                if let centroid = moment.centroid { namedCoordinates.append(centroid) }
            } else if let centroid = moment.centroid {
                unnamedCoordinates.append(centroid)
            }
        }

        // Unnamed locations near a named one are that place; the rest are grouped by distance.
        var extraPlaces: [GeoCoordinate] = []
        for coordinate in unnamedCoordinates {
            let nearNamed = namedCoordinates.contains { $0.distance(to: coordinate) <= unnamedPlaceRadius }
            let nearExtra = extraPlaces.contains { $0.distance(to: coordinate) <= unnamedPlaceRadius }
            if !nearNamed && !nearExtra { extraPlaces.append(coordinate) }
        }

        return StoryStatistics(
            memoryCount: photos + videos,
            photoCount: photos,
            videoCount: videos,
            momentCount: moments,
            chapterCount: chapters.count,
            placeCount: namedPlaces.count + extraPlaces.count,
            firstMemoryDate: first,
            lastMemoryDate: last
        )
    }
}
