import Foundation

/// A run of consecutive moments spent away from home in the same area — typically a trip
/// ("Kaş • August 2025" containing a day in Kekova).
///
/// Hierarchy: Story → Chapter → Moment → Asset. Moments outside any trip have no chapter.
public struct Chapter: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var momentIDs: [MomentID]
    public var startDate: Date
    public var endDate: Date
    public var centroid: GeoCoordinate?
    public var place: PlaceName?
    public var title: MomentTitle

    public init(
        id: UUID,
        momentIDs: [MomentID],
        startDate: Date,
        endDate: Date,
        centroid: GeoCoordinate? = nil,
        place: PlaceName? = nil,
        title: MomentTitle = MomentTitle(primary: "")
    ) {
        self.id = id
        self.momentIDs = momentIDs
        self.startDate = startDate
        self.endDate = endDate
        self.centroid = centroid
        self.place = place
        self.title = title
    }
}
