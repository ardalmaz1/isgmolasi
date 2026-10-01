import Foundation
@testable import ReliveCore

/// A small, hand-built story for creation tests:
///
/// - 2025-08: a trip to Kaş (chapter) with two moments, "Kaş" (Aug 6, 8 photos) and "Kekova"
///   (Aug 7, 5 photos, one of them a screenshot).
/// - 2025-09: "Moda Evening" in Kadıköy (Sep 12, 4 photos + 1 video) and "September Afternoon"
///   without a place (Sep 20, 2 photos).
/// - 2026-03: "Spring Walk" (Mar 3, 3 photos), hidden by the user.
/// - 2026-04: "Coffee" (Apr 1, 6 photos, landscape).
/// - An undated moment with 2 photos.
struct CreationFixture {
    var story: Story
    var assets: [AssetID: MemoryAsset]
    var userStates: [MomentID: MomentUserState] = [:]
    var unavailable: Set<AssetID> = []

    static let tripID = StableIdentifier.uuid(namespace: "fixture", key: "trip")

    static func momentID(_ key: String) -> MomentID {
        StableIdentifier.uuid(namespace: "fixture", key: key)
    }

    var library: CreationLibrary {
        CreationLibrary(story: story, assets: assets, userStates: userStates, unavailableAssetIDs: unavailable, calendar: testCalendar)
    }

    func moment(_ key: String) -> Moment {
        story.moment(id: Self.momentID(key))!
    }

    static func make() -> CreationFixture {
        var assets: [MemoryAsset] = []
        var moments: [Moment] = []

        func addMoment(
            _ key: String,
            title: String,
            start: Date,
            photos: Int,
            width: Int = 3024,
            height: Int = 4032,
            place: String? = nil,
            location: GeoCoordinate? = nil,
            chapter: UUID? = nil,
            kind: Moment.Kind = .event,
            extras: [MemoryAsset] = [],
            dated: Bool = true
        ) {
            var members: [MemoryAsset] = []
            for index in 0..<photos {
                let quality = 0.3 + Double((index * 7) % 5) / 10
                members.append(makeAsset(
                    "\(key)-\(index)",
                    at: dated ? start.addingTimeInterval(Double(index) * 600) : nil,
                    location: location,
                    width: width,
                    height: height,
                    analysis: analysis(sharpness: quality, aesthetics: quality)
                ))
            }
            members += extras
            assets += members
            let ids = members.map(\.id)
            moments.append(Moment(
                id: momentID(key),
                kind: kind,
                assetIDs: ids,
                featuredAssetIDs: ids,
                heroAssetID: ids.first,
                startDate: dated ? start : nil,
                endDate: dated ? start.addingTimeInterval(Double(max(0, photos - 1)) * 600) : nil,
                centroid: location,
                place: place.map { PlaceName(name: $0, region: "Antalya") },
                title: MomentTitle(primary: title),
                chapterID: chapter
            ))
        }

        addMoment("kas", title: "Kaş", start: date(2025, 8, 6, 10), photos: 8, place: "Kaş", location: Places.kas, chapter: tripID)
        addMoment(
            "kekova", title: "Kekova", start: date(2025, 8, 7, 11), photos: 4, place: "Kekova", location: Places.kekova, chapter: tripID,
            extras: [makeAsset("kekova-shot", at: date(2025, 8, 7, 15), location: Places.kekova, traits: .screenshot)]
        )
        addMoment(
            "moda", title: "Moda Evening", start: date(2025, 9, 12, 19), photos: 4, place: "Kadıköy", location: Places.moda,
            extras: [makeAsset("moda-video", at: date(2025, 9, 12, 20), location: Places.moda, kind: .video)]
        )
        addMoment("afternoon", title: "September Afternoon", start: date(2025, 9, 20, 15), photos: 2)
        addMoment("spring", title: "Spring Walk", start: date(2026, 3, 3, 10), photos: 3)
        addMoment("coffee", title: "Coffee", start: date(2026, 4, 1, 9), photos: 6, width: 4032, height: 3024)
        addMoment("undated", title: "Without a date", start: date(2000, 1, 1), photos: 2, kind: .undated, dated: false)

        let chapter = Chapter(
            id: tripID,
            momentIDs: [momentID("kas"), momentID("kekova")],
            startDate: date(2025, 8, 6, 10),
            endDate: date(2025, 8, 7, 15),
            centroid: Places.kas,
            place: PlaceName(name: "Kaş", region: "Antalya"),
            title: MomentTitle(primary: "Kaş", secondary: "August 2025")
        )
        var fixture = CreationFixture(
            story: Story(generatedAt: date(2026, 4, 2), moments: moments, chapters: [chapter]),
            assets: Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        )
        fixture.userStates[momentID("spring")] = MomentUserState(isHidden: true)
        return fixture
    }
}
