import Foundation
import Testing
@testable import ReliveCore

@Suite("FoundForYouService")
struct FoundForYouTests {
    let service = FoundForYouService(calendar: testCalendar)
    let now = date(2026, 9, 28, 9)

    func moment(_ id: String, start: Date, assets: [MemoryAsset], place: String? = nil) -> Moment {
        Moment(
            id: StableIdentifier.uuid(namespace: "test", key: id),
            kind: .event,
            assetIDs: assets.map(\.id),
            featuredAssetIDs: assets.map(\.id),
            heroAssetID: assets.first?.id,
            startDate: start,
            endDate: start,
            place: place.map { PlaceName(name: $0) },
            title: MomentTitle(primary: id)
        )
    }

    func fixture() -> (Story, [AssetID: MemoryAsset]) {
        let old = [makeAsset("old-1", at: date(2024, 8, 7, 19), analysis: analysis(faces: 2, faceQuality: 0.8, sharpness: 0.8))]
        let older = [makeAsset("older-1", at: date(2023, 5, 1, 12), analysis: analysis(sharpness: 0.6))]
        let recent = [makeAsset("recent-1", at: date(2026, 9, 20, 12), analysis: analysis(faces: 2, faceQuality: 1, sharpness: 1))]
        let moments = [
            moment("older", start: date(2023, 5, 1, 12), assets: older),
            moment("old", start: date(2024, 8, 7, 19), assets: old, place: "Kaş"),
            moment("recent", start: date(2026, 9, 20, 12), assets: recent),
        ]
        let assets = Dictionary(uniqueKeysWithValues: (old + older + recent).map { ($0.id, $0) })
        return (Story(generatedAt: now, moments: moments, chapters: []), assets)
    }

    @Test("Prefers an older, good memory over a very recent one")
    func prefersOlder() throws {
        let (story, assets) = fixture()
        let found = try #require(service.select(story: story, assets: assets, userStates: [:], isAvailable: { _ in true }, now: now))
        #expect(found.assetID != "recent-1")
        #expect(!found.ageDescription.isEmpty)
    }

    @Test("Hidden and excluded moments are never chosen")
    func respectsHiding() {
        let (story, assets) = fixture()
        var states: [MomentID: MomentUserState] = [:]
        for moment in story.moments where moment.title.primary != "recent" {
            states[moment.id] = MomentUserState(isHidden: moment.title.primary == "old", isExcludedFromSurfacing: moment.title.primary == "older")
        }
        let found = service.select(story: story, assets: assets, userStates: states, isAvailable: { _ in true }, now: now)
        #expect(found?.assetID == "recent-1")
    }

    @Test("Recently surfaced moments rest")
    func cooldown() throws {
        let (story, assets) = fixture()
        let first = try #require(service.select(story: story, assets: assets, userStates: [:], isAvailable: { _ in true }, now: now))
        let states = [first.momentID: MomentUserState(lastSurfacedAt: now.addingTimeInterval(-86_400), surfacedCount: 1)]
        let second = try #require(service.select(story: story, assets: assets, userStates: states, isAvailable: { _ in true }, now: now))
        #expect(second.momentID != first.momentID)
    }

    @Test("Same day, same answer")
    func deterministic() {
        let (story, assets) = fixture()
        let first = service.select(story: story, assets: assets, userStates: [:], isAvailable: { _ in true }, now: now)
        let second = service.select(story: story, assets: assets, userStates: [:], isAvailable: { _ in true }, now: now.addingTimeInterval(3600))
        #expect(first == second)
    }

    @Test("Unavailable photos are skipped and an empty story gives nothing")
    func unavailable() {
        let (story, assets) = fixture()
        #expect(service.select(story: story, assets: assets, userStates: [:], isAvailable: { _ in false }, now: now) == nil)
        #expect(service.select(story: .empty, assets: [:], userStates: [:], isAvailable: { _ in true }, now: now) == nil)
    }

    @Test("Age descriptions are plain and factual")
    func ageDescriptions() {
        let describer = RelativeAgeDescriber(calendar: testCalendar)
        #expect(describer.describe(date(2024, 9, 27), now: now) == "2 years ago this week")
        #expect(describer.describe(date(2024, 5, 1), now: now) == "2 years ago")
        #expect(describer.describe(date(2025, 6, 1), now: now) == "A year ago")
        #expect(describer.describe(date(2026, 4, 1), now: now) == "5 months ago")
        #expect(describer.describe(date(2026, 9, 1), now: now) == "A few weeks ago")
    }
}
