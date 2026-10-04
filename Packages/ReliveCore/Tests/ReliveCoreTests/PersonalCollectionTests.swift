import Foundation
import Testing
@testable import ReliveCore

/// v0.4: favorites, saved creations and drafts — and the v0.3.1 rule that a creation describes
/// only its own photos.
@Suite("Favorites")
struct FavoritesTests {
    let now = date(2026, 10, 10)

    @Test("Favoriting and unfavoriting a memory; changes are reported once")
    func memoryFavorite() {
        var favorites = FavoriteCollection()
        let added = favorites.set(.memory, "kas-1", isFavorite: true, at: now)
        let again = favorites.set(.memory, "kas-1", isFavorite: true, at: now.addingTimeInterval(60))
        #expect(added && !again)
        #expect(favorites.contains(.memory, "kas-1"))
        #expect(favorites.favoritedAt(.memory, "kas-1") == now, "favoriting again keeps the first date")
        let removed = favorites.set(.memory, "kas-1", isFavorite: false, at: now)
        #expect(removed)
        #expect(!favorites.contains(.memory, "kas-1"))
        #expect(favorites.count == 0)
    }

    @Test("A favorite moment is independent of its photos' favorites")
    func momentIndependent() {
        let kas = CreationFixture.make().moment("kas")
        var favorites = FavoriteCollection()
        favorites.set(.moment, kas.id.uuidString, isFavorite: true, at: now)
        #expect(favorites.momentIDs == [kas.id])
        #expect(favorites.memoryIDs.isEmpty, "favoriting a moment doesn't favorite its photos")

        var photos = FavoriteCollection()
        photos.set(.memory, kas.assetIDs[0], isFavorite: true, at: now)
        #expect(photos.momentIDs.isEmpty, "favoriting a photo doesn't favorite its moment")
    }

    @Test("Records survive a round trip, and duplicates collapse to the earliest")
    func records() {
        let records = [
            FavoriteRecord(kind: .memory, identifier: "a", favoritedAt: now),
            FavoriteRecord(kind: .memory, identifier: "a", favoritedAt: now.addingTimeInterval(-60)),
            FavoriteRecord(kind: .creation, identifier: UUID().uuidString, favoritedAt: now),
        ]
        let favorites = FavoriteCollection(records)
        #expect(favorites.count == 2)
        #expect(favorites.favoritedAt(.memory, "a") == now.addingTimeInterval(-60))
        #expect(FavoriteCollection(favorites.records) == favorites)
    }

    @Test("A hundred and more favorites have one deterministic order")
    func manyFavorites() {
        var assets: [MemoryAsset] = []
        var moments: [Moment] = []
        for index in 0..<130 {
            let asset = makeAsset("p\(index)", at: date(2025, 1 + index % 12, 1 + index % 28, 9 + index % 10))
            assets.append(asset)
            moments.append(Moment(id: UUID(), kind: .event, assetIDs: [asset.id], featuredAssetIDs: [asset.id],
                                  startDate: asset.creationDate, endDate: asset.creationDate, title: MomentTitle(primary: "M\(index)")))
        }
        moments.sort { $0.sortDate < $1.sortDate }
        var library = CreationLibrary(story: Story(generatedAt: now, moments: moments, chapters: []),
                                      assets: Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) }),
                                      userStates: [:], unavailableAssetIDs: [], calendar: testCalendar)
        let ids = assets.map(\.id)
        library.favoriteAssetIDs = Set(ids.shuffled())
        let first = library.favoritePhotos
        library.favoriteAssetIDs = Set(ids.reversed())
        #expect(library.favoritePhotos == first, "the order doesn't depend on how they were added")
        #expect(first.count == 130)
        #expect(first == first.sorted(by: library.chronologicalOrder))

        var collection = FavoriteCollection()
        for (offset, id) in ids.enumerated() { collection.set(.memory, id, isFavorite: true, at: now.addingTimeInterval(Double(offset % 7))) }
        #expect(collection.records == FavoriteCollection(collection.records.shuffled()).records)
    }

    @Test("Favorites that can't be used now are kept but not offered")
    func unavailableFavorites() {
        var fixture = CreationFixture.make()
        fixture.unavailable = ["kas-2"]
        var library = fixture.library
        library.favoriteAssetIDs = ["kas-1", "kas-2", "spring-0", "kekova-shot", "moda-video", "gone-from-the-story"]
        #expect(library.favoritePhotos == ["kas-1"], "deleted, hidden, screenshot, video and unknown favorites aren't offered")
        library.favoriteMomentIDs = [fixture.moment("kas").id, fixture.moment("spring").id]
        #expect(library.favoriteMoments.map(\.id) == [fixture.moment("kas").id], "a hidden moment isn't offered")
    }
}

@Suite("Favorites as a creation source")
struct FavoritesSourceTests {
    private func library(favorites: Set<AssetID>) -> CreationLibrary {
        var library = CreationFixture.make().library
        library.favoriteAssetIDs = favorites
        return library
    }

    @Test("The Favorites source holds only eligible favorites")
    func onlyFavorites() {
        let library = library(favorites: ["kas-1", "moda-0", "kekova-shot"])
        #expect(library.availablePhotos(for: .favorites) == ["kas-1", "moda-0"])
        #expect(Set(library.initialPhotos(for: .favorites, limit: 6)) == ["kas-1", "moda-0"])
    }

    @Test("Too few favorites: a gentle shortfall, never padding")
    func tooFew() {
        let two = library(favorites: ["kas-1", "moda-0"])
        #expect(throws: CreationShortfall.self) { try StoryDesigner(library: two).design(source: .favorites, style: .minimal).get() }
        #expect(MemoryBookBuilder(library: two).makeBook(from: .favorites, now: Date()) == .failure(.notEnoughPhotos(available: 2, required: 6)))
        #expect(library(favorites: []).availablePhotos(for: .favorites).isEmpty)
    }

    @Test("Favorites are described by their own photos")
    func metadata() throws {
        let septemberOnly = library(favorites: ["moda-0", "moda-1", "afternoon-0"])
        #expect(septemberOnly.facts(for: .favorites, photos: septemberOnly.favoritePhotos).title == .month(MonthKey(year: 2025, month: 9)))
        let twoMonths = library(favorites: ["kas-0", "kas-1", "moda-0"])
        #expect(twoMonths.facts(for: .favorites, photos: twoMonths.favoritePhotos).title == .year(2025), "August and September: not September")
        let twoYears = library(favorites: ["kas-0", "coffee-0", "coffee-1"])
        #expect(twoYears.facts(for: .favorites, photos: twoYears.favoritePhotos).title == nil, "2025 and 2026: not 2026")
        let story = try StoryDesigner(library: twoMonths).design(source: .favorites, style: .film).get()
        #expect(story.cards[0].title == .year(2025))
    }

    @Test("Favorites are preferred among similar photos, without breaking chronology")
    func preference() {
        let plain = CreationFixture.make().library
        let kas = CreationFixture.make().moment("kas")
        let pickedWithout = plain.spreadPick(kas.assetIDs, count: 4)
        let notPicked = kas.assetIDs.first { !pickedWithout.contains($0) }!
        var favored = plain
        favored.favoriteAssetIDs = [notPicked]
        let pickedWith = favored.spreadPick(kas.assetIDs, count: 4)
        #expect(pickedWith.contains(notPicked))
        #expect(pickedWith == pickedWith.sorted(by: favored.chronologicalOrder))
        #expect(pickedWith.count == 4)
    }
}

@Suite("Saved creations and drafts")
struct SavedCreationTests {
    let now = date(2026, 10, 10)
    let fixture = CreationFixture.make()

    private func collage(_ photos: [AssetID], source: CreationSource) -> SavedCreation {
        var creation = SavedCreation(
            kind: .collage, createdAt: now, source: source,
            collage: CollageState(photoIDs: photos, style: .film, aspectRatio: .story, showsTitle: false, showsDate: true, showsPlace: false)
        )
        creation.captureSnapshots(from: fixture.library)
        return creation
    }

    @Test("A collage keeps its photos, order, style, shape and caption choices")
    func collageRoundTrip() throws {
        let creation = collage(["kas-3", "kas-0", "kekova-1"], source: .trip(CreationFixture.tripID))
        let restored = try JSONDecoder().decode(SavedCreation.self, from: JSONEncoder().encode(creation))
        #expect(restored == creation)
        #expect(restored.collage?.photoIDs == ["kas-3", "kas-0", "kekova-1"])
        #expect(restored.collage?.style == .film && restored.collage?.aspectRatio == .story)
        #expect(restored.collage?.showsTitle == false && restored.collage?.showsPlace == false)
    }

    @Test("A story keeps its cards: order, layouts, photos and show/hide choices")
    func storyRoundTrip() throws {
        var design = try StoryDesigner(library: fixture.library).design(source: .trip(CreationFixture.tripID), style: .travel).get()
        let pair = try #require(design.cards.first { $0.photos.count == 2 })
        design.cycleLayout(of: pair.id)
        design.cards[0].showsDate = false
        let creation = SavedCreation(kind: .story, createdAt: now, source: .trip(CreationFixture.tripID), story: StoryState(design: design))
        let restored = try JSONDecoder().decode(SavedCreation.self, from: JSONEncoder().encode(creation))
        #expect(restored.story?.design == design)
        #expect(restored.story?.design.cards.map(\.layout) == design.cards.map(\.layout))
        #expect(restored.story?.design.cards[0].showsDate == false)
        #expect(restored.photoIDs == design.photoIDs)
    }

    @Test("A draft becomes the saved creation — the same record, no duplicate")
    func lifecycle() {
        var creation = collage(["kas-0", "kas-1"], source: .moment(fixture.moment("kas").id))
        #expect(creation.isDraft)
        let id = creation.id
        creation.markSaved(at: now.addingTimeInterval(60))
        #expect(creation.status == .saved && creation.id == id)
        #expect(creation.savedAt == now.addingTimeInterval(60))
        creation.markExported(at: now.addingTimeInterval(120))
        #expect(creation.exportedAt == now.addingTimeInterval(120))
        #expect(creation.savedAt == now.addingTimeInterval(60), "saving again keeps when it was first saved")
    }

    @Test("Snapshots keep a creation drawable after its photos leave the story; never their pixels or analysis")
    func snapshots() {
        let creation = collage(["kas-0", "moda-1", "afternoon-0"], source: .photos(["kas-0", "moda-1", "afternoon-0"]))
        #expect(creation.assetSnapshots.map(\.id) == ["kas-0", "moda-1", "afternoon-0"])
        #expect(creation.assetSnapshots.allSatisfy { $0.analysis == nil })

        // After Start Over: the story is empty, but the photos are still in the photo library.
        let empty = CreationLibrary(story: .empty, assets: [:], userStates: [:], unavailableAssetIDs: [], calendar: testCalendar)
        let library = creation.creationLibrary(base: empty)
        #expect(creation.missingPhotos(in: library).isEmpty)
        let facts = creation.facts(in: library)
        #expect(facts.title == .year(2025), "August and September, from the photos' own dates")
        #expect(facts.place == nil, "place names come back with the story, not from snapshots")
    }

    @Test("A photo deleted later is missing, not replaced")
    func missing() {
        var fixture = fixture
        fixture.unavailable = ["kas-1"]
        let creation = collage(["kas-0", "kas-1", "kas-2"], source: .moment(fixture.moment("kas").id))
        let library = creation.creationLibrary(base: fixture.library)
        #expect(creation.missingPhotos(in: library) == ["kas-1"])
        #expect(creation.photoIDs == ["kas-0", "kas-1", "kas-2"], "nothing is swapped in")
        #expect(creation.facts(in: library).title == .named("Kaş"))
    }

    @Test("A creation's facts follow its photos, not where it started")
    func factsFollowPhotos() {
        let september = MonthKey(year: 2025, month: 9)
        let mixed = collage(["kas-0", "moda-0", "afternoon-1"], source: .month(september))
        #expect(mixed.facts(in: fixture.library).title != .month(september))
        let onlySeptember = collage(["moda-0", "afternoon-1"], source: .month(september))
        #expect(onlySeptember.facts(in: fixture.library).title == .month(september))
    }
}

@Suite("Story editing keeps facts true")
struct StoryEditingFactsTests {
    let fixture = CreationFixture.make()

    @Test("Replacing a photo with one from another month updates the opening too")
    func openingFollowsReplacement() throws {
        var design = try StoryDesigner(library: fixture.library).design(source: .moment(fixture.moment("kas").id), style: .minimal).get()
        #expect(design.cards[0].title == .named("Kaş"))
        let card = try #require(design.cards.first { $0.role == .photo })
        let ok = design.replacePhoto(cardID: card.id, slot: 0, with: "coffee-1", library: fixture.library)
        #expect(ok)
        #expect(design.cards[0].title == nil, "Kaş in 2025 and a coffee in 2026: no single title any more")
        #expect(design.cards[0].place == nil)
    }

    @Test("Photos that are gone leave the story without anything unrelated taking their place")
    func removingMissing() throws {
        var design = try StoryDesigner(library: fixture.library).design(source: .trip(CreationFixture.tripID), style: .film).get()
        let original = Set(design.photoIDs)
        let lead = try #require(design.cards[0].photos.first)
        let other = try #require(design.cards.first { $0.role == .photo }?.photos.first)
        design.removingPhotos([lead, other], library: fixture.library)
        #expect(!design.photoIDs.contains(lead) && !design.photoIDs.contains(other))
        #expect(Set(design.photoIDs).isSubset(of: original), "nothing unrelated is added")
        #expect(design.cards[0].role == .opening && design.cards[0].photos.count == 1)
        #expect(design.cards.allSatisfy { $0.photos.count == $0.layout.photoCount })
        #expect(StoryDesigner.cardRange.lowerBound - 1 <= design.cards.count)
    }

    @Test("Removing a card keeps the remaining facts true")
    func removeCardRefreshes() throws {
        var design = try StoryDesigner(library: fixture.library).design(source: .photos(["kas-0", "kas-1", "kas-2", "coffee-0", "coffee-1"]), style: .minimal).get()
        let coffeeCards = design.cards.filter { $0.role == .photo && $0.photos.contains { $0.hasPrefix("coffee") } }
        for card in coffeeCards { design.removeCard(card.id, library: fixture.library) }
        if !design.photoIDs.contains(where: { $0.hasPrefix("coffee") }) {
            #expect(design.cards[0].dateSpan.map { testCalendar.component(.year, from: $0.end) } == 2025, "the opening no longer spans 2026")
        }
    }
}
