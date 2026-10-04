import Foundation
import Testing
@testable import ReliveCore

/// Metadata follows the photo: what a creation says about its photos comes from the photos
/// themselves, never from the screen or month it was started from.
@Suite("Creation metadata")
struct CreationMetadataTests {
    private let aliaga = PlaceName(name: "Aliağa", region: "İzmir")
    private let kas = PlaceName(name: "Kaş", region: "Antalya")
    private let aliagaPoint = GeoCoordinate(latitude: 38.7996, longitude: 26.9707)

    private func photo(_ id: String, _ date: Date?, place: PlaceName? = nil, at coordinate: GeoCoordinate? = nil) -> CreationAsset {
        CreationAsset(id: id, source: .photoLibrary, creationDate: date, coordinate: coordinate, place: place, pixelWidth: 3024, pixelHeight: 4032)
    }

    private func summarize(_ assets: [CreationAsset]) -> CreationMetadataSummary {
        CreationMetadata.summarize(assets, calendar: testCalendar)
    }

    // MARK: - The seven required selections

    @Test("1. Six photos from September 2026 are September 2026")
    func allSeptember() {
        let summary = summarize((0..<6).map { photo("s\($0)", date(2026, 9, 3 + $0 * 4, 19)) })
        #expect(summary.period == .month(MonthKey(year: 2026, month: 9)))
        #expect(CreationMetadata.periodTitle(for: summary) == .month(MonthKey(year: 2026, month: 9)))
    }

    @Test("2. Three August and three September photos are not September")
    func augustAndSeptember() {
        let photos = (0..<3).map { photo("a\($0)", date(2026, 8, 10 + $0, 19)) } + (0..<3).map { photo("s\($0)", date(2026, 9, 5 + $0, 19)) }
        let summary = summarize(photos)
        #expect(summary.period == .year(2026))
        #expect(CreationMetadata.periodTitle(for: summary) != .month(MonthKey(year: 2026, month: 9)))
        #expect(CreationMetadata.periodTitle(for: summary) != .month(MonthKey(year: 2026, month: 8)))
        #expect(summary.dateSpan == DateSpan(start: date(2026, 8, 10, 19), end: date(2026, 9, 7, 19)))
    }

    @Test("3. Photos from 2025 and 2026 get no single-year label")
    func twoYears() {
        let summary = summarize([photo("old", date(2025, 12, 30)), photo("new", date(2026, 1, 2))])
        #expect(summary.period == .years(first: 2025, last: 2026))
        #expect(CreationMetadata.periodTitle(for: summary) == nil)
        #expect(!CreationMetadata.fits(summary, year: 2026, calendar: testCalendar))
        #expect(!CreationMetadata.fits(summary, year: 2025, calendar: testCalendar))
    }

    @Test("4. Photos all from Aliağa may be called Aliağa")
    func onePlace() {
        let summary = summarize((0..<4).map { photo("p\($0)", date(2026, 9, 18), place: aliaga, at: aliagaPoint) })
        #expect(summary.place == aliaga)
        #expect(summary.coordinate != nil)
    }

    @Test("5. Aliağa and Kaş together are not labelled Aliağa")
    func twoPlaces() {
        let summary = summarize([
            photo("a", date(2026, 9, 18), place: aliaga, at: aliagaPoint),
            photo("k", date(2026, 8, 6), place: kas, at: Places.kas),
        ])
        #expect(summary.place == nil)
        #expect(summary.coordinate == nil, "photos hundreds of kilometres apart share no location")
    }

    @Test("6. Photos without a location get no place or coordinate")
    func noLocation() {
        let summary = summarize([photo("a", date(2026, 9, 18)), photo("b", date(2026, 9, 18))])
        #expect(summary.place == nil)
        #expect(summary.coordinate == nil)
        // One photo without a place is enough to withhold it.
        let mixed = summarize([photo("a", date(2026, 9, 18), place: aliaga), photo("b", date(2026, 9, 18))])
        #expect(mixed.place == nil)
    }

    @Test("7. Photos without a date get no month or year")
    func noDate() {
        let undated = summarize([photo("a", nil), photo("b", nil)])
        #expect(undated.period == nil)
        #expect(undated.dateSpan == nil)
        #expect(CreationMetadata.periodTitle(for: undated) == nil)
        // One undated photo among September ones: the whole set can't be called September.
        let mixed = summarize([photo("a", date(2026, 9, 3)), photo("b", date(2026, 9, 9)), photo("c", nil)])
        #expect(mixed.period == nil)
        #expect(mixed.dateSpan == nil)
        #expect(mixed.datedCount == 2)
    }

    // MARK: - Photo Library photos

    @Test("A photo chosen from the photo library keeps its own date, location and size")
    func photoLibraryAsset() {
        let fixture = CreationFixture.make()
        let picked = makeAsset("library-1", at: date(2024, 5, 4, 18, 30), location: aliagaPoint, width: 4032, height: 3024)
        let library = fixture.library.addingPhotoLibraryAssets([picked])
        let asset = library.creationAsset("library-1")
        #expect(asset?.source == .photoLibrary)
        #expect(asset?.creationDate == date(2024, 5, 4, 18, 30))
        #expect(asset?.coordinate == aliagaPoint)
        #expect(asset?.pixelWidth == 4032 && asset?.pixelHeight == 3024)
        #expect(asset?.orientation == .landscape)
        #expect(asset?.place == nil, "no place name is looked up for a creation")
        #expect(asset?.momentID == nil && asset?.tripID == nil)
        #expect(library.isUsable("library-1"))
        #expect(library.story == fixture.story, "photo library picks never join the story")
    }

    @Test("A photo library pick that is already a memory keeps its memory metadata")
    func photoLibraryPickOfAMemory() {
        let fixture = CreationFixture.make()
        let copy = makeAsset("kas-0", at: date(2030, 1, 1))
        let library = fixture.library.addingPhotoLibraryAssets([copy])
        let asset = library.creationAsset("kas-0")
        #expect(asset?.source == .relive)
        #expect(asset?.creationDate == date(2025, 8, 6, 10))
        #expect(asset?.place?.name == "Kaş")
    }

    @Test("Photo library photos from several months are described by their own dates")
    func photoLibraryFacts() {
        let picks = [
            makeAsset("l1", at: date(2026, 8, 30, 19)),
            makeAsset("l2", at: date(2026, 9, 5, 19)),
            makeAsset("l3", at: date(2026, 10, 2, 19)),
        ]
        let library = CreationFixture.make().library.addingPhotoLibraryAssets(picks)
        let facts = library.facts(forPhotos: picks.map(\.id))
        #expect(facts.title == .year(2026))
        #expect(facts.place == nil)
        #expect(facts.dateSpan == DateSpan(start: date(2026, 8, 30, 19), end: date(2026, 10, 2, 19)))
    }

    // MARK: - The September bug

    @Test("A September creation given August photos is no longer called September")
    func sourceTitleFollowsPhotos() {
        let library = CreationFixture.make().library
        let september = MonthKey(year: 2025, month: 9)
        let mixed = ["kas-0", "kas-1", "moda-0", "moda-1", "afternoon-0", "afternoon-1"]
        let facts = library.facts(for: .month(september), photos: mixed)
        #expect(facts.title != .month(september))
        #expect(facts.title == .year(2025))
        // Still September when every photo is.
        #expect(library.facts(for: .month(september), photos: ["moda-0", "afternoon-1"]).title == .month(september))
    }

    @Test("A year creation given photos from another year is no longer called that year")
    func yearTitleFollowsPhotos() {
        let library = CreationFixture.make().library
        #expect(library.facts(for: .year(2026), photos: ["coffee-0", "kas-0"]).title == nil)
        #expect(library.facts(for: .year(2026), photos: ["coffee-0", "coffee-1"]).title == .year(2026))
    }

    @Test("A trip creation given photos from outside the trip is no longer called the trip")
    func tripTitleFollowsPhotos() {
        let library = CreationFixture.make().library
        let facts = library.facts(for: .trip(CreationFixture.tripID), photos: ["kas-0", "moda-0"])
        #expect(facts.title != .named("Kaş"))
        #expect(facts.place == nil)
    }

    @Test("Favorites are a source of their own, in the order they were taken")
    func favorites() {
        var fixture = CreationFixture.make()
        for id in ["moda-1", "kas-3", "coffee-2"] { fixture.assets[id]?.isFavorite = true }
        let library = fixture.library
        #expect(library.favoritePhotos == ["kas-3", "moda-1", "coffee-2"])
        #expect(library.availablePhotos(for: .favorites) == ["kas-3", "moda-1", "coffee-2"])
        #expect(library.facts(for: .favorites, photos: library.favoritePhotos).title == nil, "2025 and 2026: no single label")
    }
}
