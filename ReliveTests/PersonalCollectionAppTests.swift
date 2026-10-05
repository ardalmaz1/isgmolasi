import Photos
import ReliveCore
import SwiftUI
import UIKit
import XCTest
@testable import Relive

// v0.4: favorites, saved creations and drafts, through the real store, editors and export
// controller. Like the other hosted tests, nothing touches PhotoKit or SwiftData on disk.

@MainActor
enum CollectionTestStore {
    /// The creation test story, with an analytics tracker the test can read.
    static func make(analytics: InMemoryAnalyticsTracker = InMemoryAnalyticsTracker()) -> (StoryStore, InMemoryStoryRepository) {
        let (story, assets) = CreationTestLibrary.makeStory()
        let repository = InMemoryStoryRepository(assets: assets)
        repository.story = story
        return (reopen(repository, analytics: analytics), repository)
    }

    /// A new store over the same storage — the app after a restart.
    static func reopen(_ repository: InMemoryStoryRepository, libraryAssets: [MemoryAsset]? = nil, analytics: InMemoryAnalyticsTracker = InMemoryAnalyticsTracker()) -> StoryStore {
        StoryStore(
            repository: repository,
            photoLibrary: FakePhotoLibrary(assets: libraryAssets ?? repository.assets),
            analyzer: InstantAnalyzer(),
            placeResolver: NoPlaceLookups(),
            analytics: analytics
        )
    }
}

/// Saves "to Photos" without PhotoKit, handing out the identifiers it is given.
final class FakeCreationSaver: CreationSaving, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [AssetID]

    init(identifiers: [AssetID]) {
        queue = identifiers
    }

    func save(_ jpegs: [Data]) async throws -> [AssetID] {
        lock.withLock {
            let ids = Array(queue.prefix(jpegs.count))
            queue.removeFirst(ids.count)
            return ids
        }
    }
}

@MainActor
final class FavoritesStoreTests: XCTestCase {
    func testFavoritesPersistAndNeverTouchThePhotosOrTheStory() {
        let analytics = InMemoryAnalyticsTracker()
        let (store, repository) = CollectionTestStore.make(analytics: analytics)
        let trip = store.story.moments[0]
        let photo = trip.assetIDs[2]
        let assetsBefore = store.assets
        let storyBefore = store.story

        store.setFavorite(.memory, photo, isFavorite: true)
        store.setFavorite(.memory, photo, isFavorite: true) // again: no duplicate
        XCTAssertTrue(store.isFavorite(.memory, photo))
        XCTAssertEqual(repository.favorites.count, 1)
        XCTAssertEqual(store.assets, assetsBefore, "the photo's own metadata (and Apple's favorite flag) is untouched")
        XCTAssertEqual(store.story, storyBefore, "clustering and chronology are untouched")
        XCTAssertEqual(analytics.events.filter { $0.name == .favoriteAdded }.count, 1)
        XCTAssertEqual(analytics.events.last?.properties, ["kind": "memory"], "only the kind is recorded")

        // A restart finds it.
        let reopened = CollectionTestStore.reopen(repository)
        XCTAssertTrue(reopened.isFavorite(.memory, photo))
        XCTAssertEqual(reopened.favoriteMemories.map(\.id), [photo])

        reopened.toggleFavorite(.memory, photo)
        XCTAssertFalse(reopened.isFavorite(.memory, photo))
        XCTAssertTrue(repository.favorites.isEmpty)
        XCTAssertFalse(CollectionTestStore.reopen(repository).isFavorite(.memory, photo))
    }

    /// A moment's favorite and its photos' favorites are separate, both ways.
    func testMomentAndPhotoFavoritesAreIndependent() {
        let (store, _) = CollectionTestStore.make()
        let trip = store.story.moments[0]
        store.setFavorite(.moment, trip.id.uuidString, isFavorite: true)
        XCTAssertTrue(trip.assetIDs.allSatisfy { !store.isFavorite(.memory, $0) }, "favoriting a moment doesn't favorite its photos")
        XCTAssertTrue(store.favoriteMemories.isEmpty)
        XCTAssertEqual(store.creationLibrary.favoriteMoments.map(\.id), [trip.id])

        let evening = store.story.moments[1]
        store.setFavorite(.memory, evening.assetIDs[0], isFavorite: true)
        XCTAssertFalse(store.isFavorite(.moment, evening.id.uuidString), "favoriting a photo doesn't favorite its moment")
        store.setFavorite(.moment, trip.id.uuidString, isFavorite: false)
        XCTAssertTrue(store.isFavorite(.memory, evening.assetIDs[0]))
        XCTAssertEqual(store.visibleFavoritesCount, 1)
    }

    /// Fast taps settle on the last state, with at most one stored record.
    func testRapidTogglingSettles() {
        let (store, repository) = CollectionTestStore.make()
        let photo = store.story.moments[0].assetIDs[0]
        for _ in 0..<41 { store.toggleFavorite(.memory, photo) }
        XCTAssertTrue(store.isFavorite(.memory, photo))
        XCTAssertEqual(repository.favorites.count, 1)
        store.toggleFavorite(.memory, photo)
        XCTAssertTrue(repository.favorites.isEmpty)
    }

    /// Favorites of photos that aren't in the story stay saved but aren't shown or offered.
    func testFavoritesOfMissingMemoriesAreKeptButNotShown() {
        let (store, repository) = CollectionTestStore.make()
        store.setFavorite(.memory, "gone-photo", isFavorite: true)
        store.setFavorite(.memory, store.story.moments[0].assetIDs[0], isFavorite: true)
        XCTAssertEqual(store.favoriteMemories.count, 1)
        XCTAssertEqual(store.creationLibrary.favoritePhotos.count, 1)
        XCTAssertEqual(repository.favorites.count, 2, "nothing is silently forgotten")
    }

    /// Start Over resets the story; favorites stay, and return with their memories.
    func testStartOverKeepsFavorites() {
        let (store, repository) = CollectionTestStore.make()
        let photo = store.story.moments[0].assetIDs[0]
        store.setFavorite(.memory, photo, isFavorite: true)
        store.resetAll()
        XCTAssertTrue(store.favoriteMemories.isEmpty, "no story, nothing to show")
        XCTAssertTrue(store.isFavorite(.memory, photo))
        XCTAssertEqual(repository.favorites.count, 1)
    }

    func testCollageFromFavoritesUsesExactlyTheFavorites() {
        let (store, _) = CollectionTestStore.make()
        let trip = store.story.moments[0]
        let evening = store.story.moments[1]
        let chosen = [trip.assetIDs[1], trip.assetIDs[4], evening.assetIDs[2]]
        chosen.forEach { store.setFavorite(.memory, $0, isFavorite: true) }
        let library = store.creationLibrary
        let photos = library.initialPhotos(for: .favorites, limit: CreationLimits.collagePreselection)
        XCTAssertEqual(Set(photos), Set(chosen))
        let model = CollageEditorModel(source: .favorites, photos: photos, library: library, store: store)
        XCTAssertEqual(Set(model.photoIDs), Set(chosen))
        XCTAssertEqual(model.facts, library.facts(forPhotos: photos), "described by its photos, not by 'Favorites'")
    }

    func testStoryFromTooFewFavoritesExplains() {
        let (store, _) = CollectionTestStore.make()
        store.story.moments[0].assetIDs.prefix(2).forEach { store.setFavorite(.memory, $0, isFavorite: true) }
        let model = StoryMakerModel(source: .favorites, library: store.creationLibrary, store: store)
        XCTAssertEqual(model.shortfall, .notEnoughPhotos(available: 2, required: 3))
        XCTAssertTrue(model.cards.isEmpty, "nothing is invented to fill the gap")
    }
}

@MainActor
final class DraftLifecycleTests: XCTestCase {
    private func collage(_ store: StoryStore) -> CollageEditorModel {
        let trip = store.story.moments[0]
        return CollageEditorModel(source: .moment(trip.id), photos: Array(trip.assetIDs.prefix(4)), library: store.creationLibrary, store: store)
    }

    /// Untouched → nothing kept; a change → one draft; more changes → the same draft; Save →
    /// the same record, finished. Never a duplicate.
    func testCollageDraftLifecycle() {
        let analytics = InMemoryAnalyticsTracker()
        let (store, repository) = CollectionTestStore.make(analytics: analytics)
        let model = collage(store)
        model.flush()
        XCTAssertTrue(store.creations.isEmpty, "Relive's own first design isn't a draft")

        model.style = model.style == .film ? .grid : .film
        model.flush()
        XCTAssertEqual(store.drafts.count, 1)
        let id = store.drafts[0].id
        XCTAssertEqual(store.drafts[0].collage, model.state)

        model.showsDate = false
        model.move(from: 0, by: 1)
        model.flush()
        XCTAssertEqual(store.creations.count, 1, "edits update the draft")
        XCTAssertEqual(repository.creations[id]?.collage, model.state)

        model.markSaved()
        XCTAssertTrue(store.drafts.isEmpty)
        XCTAssertEqual(store.savedCreations.map(\.id), [id], "the draft became the creation")
        XCTAssertEqual(repository.creations.count, 1)
        XCTAssertEqual(analytics.events.filter { $0.name == .draftCreated }.count, 1)
        XCTAssertEqual(analytics.events.filter { $0.name == .creationSaved }.count, 1)
    }

    /// The draft is written by itself after a short pause — not on every change.
    /// The first change creates the draft at once (so closing the app straight away loses
    /// nothing); later changes are written after a pause, not on every change.
    func testAutosaveIsDebounced() async throws {
        let (store, _) = CollectionTestStore.make()
        let model = collage(store)
        model.style = model.style == .film ? .grid : .film
        XCTAssertEqual(store.drafts.count, 1, "the first change is kept at once")
        XCTAssertEqual(store.drafts[0].collage?.showsTitle, true)
        model.showsTitle = false
        model.showsDate = false
        XCTAssertEqual(store.drafts[0].collage?.showsTitle, true, "later changes wait for the pause")
        try await Task.sleep(for: CreationKeeper.pause + .milliseconds(700))
        XCTAssertEqual(store.drafts.count, 1)
        XCTAssertEqual(store.drafts[0].collage?.showsTitle, false)
        XCTAssertEqual(store.drafts[0].collage?.showsDate, false)
    }

    /// After a restart, a collage reopens exactly as it was.
    func testCollageReopensAfterRestart() throws {
        let (store, repository) = CollectionTestStore.make()
        let model = collage(store)
        model.style = .editorial
        model.aspectRatio = .square
        model.showsPlace = false
        model.move(from: 2, by: -1)
        let state = model.state
        model.flush()

        let reopened = CollectionTestStore.reopen(repository)
        let draft = try XCTUnwrap(reopened.drafts.first)
        let restored = try XCTUnwrap(draft.collage)
        let editor = CollageEditorModel(restoring: draft, state: restored, library: reopened.creationLibrary(for: draft), store: reopened)
        XCTAssertEqual(editor.state, state)
        XCTAssertTrue(editor.missing.isEmpty)
        XCTAssertEqual(editor.facts, draft.facts(in: reopened.creationLibrary(for: draft)))

        // Editing the reopened draft updates it; it doesn't start another.
        editor.showsTitle = false
        editor.flush()
        XCTAssertEqual(reopened.creations.count, 1)
        XCTAssertEqual(repository.creations[draft.id]?.collage?.showsTitle, false)
    }

    /// A story's cards, order, layouts, style and show/hide choices survive a restart.
    func testStoryDraftRoundTrip() throws {
        let (store, repository) = CollectionTestStore.make()
        let trip = store.story.moments[0]
        let model = StoryMakerModel(source: .moment(trip.id), library: store.creationLibrary, store: store)
        let opening = try XCTUnwrap(model.cards.first)
        model.setStyle(model.style == .film ? .editorial : .film)
        model.changeLayout(of: opening.id)
        XCTAssertEqual(model.cards.first?.layout, .coverFramed)
        if let dated = model.cards.first(where: \.hasDate) { model.toggleDate(of: dated.id) }
        let design = try XCTUnwrap(model.design)
        model.flush()

        let reopened = CollectionTestStore.reopen(repository)
        let draft = try XCTUnwrap(reopened.drafts.first)
        XCTAssertEqual(draft.kind, .story)
        let state = try XCTUnwrap(draft.story)
        XCTAssertEqual(state.design, design)
        let editor = StoryMakerModel(restoring: draft, state: state, library: reopened.creationLibrary(for: draft), store: reopened)
        XCTAssertEqual(editor.design, design)
        XCTAssertNil(editor.shortfall)
    }

    /// A reopened story with a photo that's gone: shown as missing, never redesigned or filled
    /// with another photo; Remove Missing takes it out.
    func testReopenedStoryWithAMissingPhoto() async throws {
        let (store, repository) = CollectionTestStore.make()
        let trip = store.story.moments[0]
        let model = StoryMakerModel(source: .moment(trip.id), library: store.creationLibrary, store: store)
        model.setStyle(model.style == .film ? .editorial : .film)
        model.flush()
        let design = try XCTUnwrap(model.design)
        let gone = try XCTUnwrap(design.cards.first { $0.role == .photo }?.photos.first)

        // The photo is deleted from the library.
        let reopened = CollectionTestStore.reopen(repository, libraryAssets: repository.assets.filter { $0.id != gone })
        await reopened.refreshAvailability()
        let draft = try XCTUnwrap(reopened.drafts.first)
        let library = reopened.creationLibrary(for: draft)
        XCTAssertEqual(draft.missingPhotos(in: library), [gone])

        let editor = StoryMakerModel(restoring: draft, state: try XCTUnwrap(draft.story), library: library, store: reopened)
        XCTAssertEqual(editor.missingInStory, [gone])
        XCTAssertFalse(editor.canExport)
        let aspects = Dictionary(uniqueKeysWithValues: repository.assets.map { ($0.id, $0.aspectRatio ?? 1) })
        await editor.loadPreviews(using: CreationImageSource(loader: SolidPhotosExcept(gone, aspects: aspects)))
        XCTAssertEqual(editor.design, design, "the user's story is left as it was")

        editor.removeMissingPhotos()
        let remaining = try XCTUnwrap(editor.design)
        XCTAssertFalse(remaining.photoIDs.contains(gone))
        XCTAssertTrue(Set(remaining.photoIDs).isSubset(of: Set(design.photoIDs)), "nothing unrelated is put in its place")
        XCTAssertTrue(editor.canExport)
    }

    /// A collage restored with a photo that's gone keeps its place, marked missing.
    func testReopenedCollageMarksMissingPhotos() async throws {
        let (store, repository) = CollectionTestStore.make()
        let model = collage(store)
        model.style = .grid
        model.flush()
        let gone = model.photoIDs[1]
        let reopened = CollectionTestStore.reopen(repository, libraryAssets: repository.assets.filter { $0.id != gone })
        await reopened.refreshAvailability()
        let draft = try XCTUnwrap(reopened.drafts.first)
        let editor = CollageEditorModel(restoring: draft, state: try XCTUnwrap(draft.collage), library: reopened.creationLibrary(for: draft), store: reopened)
        XCTAssertEqual(editor.photoIDs, model.photoIDs, "the order is kept")
        XCTAssertEqual(editor.missingInCollage, [gone])
        XCTAssertFalse(editor.canExport)
    }

    /// Deleting a draft or creation removes only it: the photos and the story stay, and
    /// nothing writes it back.
    func testDeletingKeepsTheSourceMemories() throws {
        let analytics = InMemoryAnalyticsTracker()
        let (store, repository) = CollectionTestStore.make(analytics: analytics)
        let assetsBefore = store.assets
        let storyBefore = store.story
        let model = collage(store)
        model.markSaved()
        let id = model.keeper.id
        store.setFavorite(.creation, id.uuidString, isFavorite: true)

        model.keeper.forget()
        store.deleteCreation(id: id)
        model.style = .film // the editor is still open for a moment
        model.flush()
        XCTAssertTrue(store.creations.isEmpty)
        XCTAssertNil(repository.creations[id])
        XCTAssertFalse(store.isFavorite(.creation, id.uuidString), "its favorite goes with it")
        XCTAssertEqual(store.assets, assetsBefore)
        XCTAssertEqual(store.story, storyBefore)
        XCTAssertNotNil(store.moment(id: store.story.moments[0].id))
        XCTAssertEqual(analytics.events.filter { $0.name == .creationDeleted }.count, 1)
    }

    /// Discarding a draft: gone from Continue Editing and from storage.
    func testDiscardingADraft() {
        let analytics = InMemoryAnalyticsTracker()
        let (store, repository) = CollectionTestStore.make(analytics: analytics)
        let model = collage(store)
        model.showsTitle = false
        model.flush()
        let id = model.keeper.id
        store.deleteCreation(id: id)
        XCTAssertTrue(store.drafts.isEmpty)
        XCTAssertTrue(repository.creations.isEmpty)
        XCTAssertEqual(analytics.events.filter { $0.name == .draftDeleted }.map(\.properties), [["kind": "collage"]])
    }

    /// Start Over keeps creations and drafts; they still describe themselves from snapshots.
    func testStartOverKeepsCreationsAndDrafts() throws {
        let (store, repository) = CollectionTestStore.make()
        let model = collage(store)
        model.markSaved()
        let draft = collage(store)
        draft.showsTitle = false
        draft.flush()
        let photos = model.photoIDs
        store.resetAll()
        XCTAssertEqual(repository.creations.count, 2)
        XCTAssertEqual(store.drafts.count, 1)
        let kept = try XCTUnwrap(store.savedCreations.first)
        XCTAssertEqual(kept.photoIDs, photos)
        let library = store.creationLibrary(for: kept)
        XCTAssertTrue(kept.missingPhotos(in: library).isEmpty, "its photos' metadata was kept with it")
        XCTAssertNotNil(kept.facts(in: library).dateSpan, "and it still knows when they were taken")
    }

    /// Books and creations are listed together, most recent first, in a stable order.
    func testKeptItemsListBooksAndCreations() throws {
        let (store, _) = CollectionTestStore.make()
        let trip = store.story.moments[0]
        let book = try MemoryBookBuilder(library: store.creationLibrary).makeBook(from: .moment(trip.id), now: Date()).get()
        store.saveBook(book, now: Date(timeIntervalSinceNow: -60))
        let model = collage(store)
        model.markSaved()
        XCTAssertEqual(store.keptItems.map(\.kind), [.collage, .book])
        store.setFavorite(.creation, book.id.uuidString, isFavorite: true)
        XCTAssertEqual(store.favoriteKeptItems.map(\.id), [book.id])
        store.deleteKept(.book(book))
        XCTAssertNil(store.book(id: book.id))
        XCTAssertFalse(store.isFavorite(.creation, book.id.uuidString))
    }
}

@MainActor
final class CreationExportExclusionTests: XCTestCase {
    /// Images saved from a reopened draft are recorded as Relive's own and never imported, and
    /// saving finishes the draft.
    func testExportsFromReopenedDraftsStayExcluded() async throws {
        let (store, repository) = CollectionTestStore.make()
        let trip = store.story.moments[0]
        let first = CollageEditorModel(source: .moment(trip.id), photos: Array(trip.assetIDs.prefix(3)), library: store.creationLibrary, store: store)
        first.style = .film
        first.flush()

        let reopened = CollectionTestStore.reopen(repository)
        let draft = try XCTUnwrap(reopened.drafts.first)
        let editor = CollageEditorModel(restoring: draft, state: try XCTUnwrap(draft.collage), library: reopened.creationLibrary(for: draft), store: reopened)
        let aspects = Dictionary(uniqueKeysWithValues: repository.assets.map { ($0.id, $0.aspectRatio ?? 1) })
        let images = CreationImageSource(loader: SolidPhotos(aspects: aspects))
        let controller = ExportController(saver: FakeCreationSaver(identifiers: ["relive-collage-1", "relive-collage-2"]))
        await controller.save(store: reopened, analytics: InMemoryAnalyticsTracker(), properties: [:], onSaved: editor.markExported) {
            [try await editor.renderExport(using: images)]
        }
        XCTAssertEqual(controller.phase, .finished("Saved to Photos"))
        XCTAssertTrue(reopened.createdAssetIDs.contains("relive-collage-1"))
        XCTAssertTrue(repository.createdAssetIDs.contains("relive-collage-1"), "remembered across launches")
        let finished = try XCTUnwrap(reopened.creation(id: draft.id))
        XCTAssertEqual(finished.status, .saved, "saving the image finished the draft")
        XCTAssertNotNil(finished.exportedAt)
        XCTAssertEqual(reopened.creations.count, 1)

        // Saving the reopened creation again is excluded too.
        await controller.save(store: reopened, analytics: InMemoryAnalyticsTracker(), properties: [:], onSaved: editor.markExported) {
            [try await editor.renderExport(using: images)]
        }
        XCTAssertTrue(reopened.createdAssetIDs.isSuperset(of: ["relive-collage-1", "relive-collage-2"]))

        // The exported images become visible to Relive (limited access): they are not memories.
        let exported = ["relive-collage-1", "relive-collage-2"].map {
            MemoryAsset(localIdentifier: $0, creationDate: Date(), pixelWidth: 2160, pixelHeight: 2700)
        }
        let withExports = CollectionTestStore.reopen(repository, libraryAssets: repository.assets + exported)
        await withExports.syncWithAccessibleAssets()
        XCTAssertNil(withExports.assets["relive-collage-1"])
        XCTAssertNil(withExports.assets["relive-collage-2"])
        await withExports.importSelection(identifiers: ["relive-collage-1"])
        XCTAssertNil(withExports.assets["relive-collage-1"])
    }

    /// Story cards saved from a favorites story are excluded the same way.
    func testExportsFromAFavoritesStoryStayExcluded() async throws {
        let (store, repository) = CollectionTestStore.make()
        store.story.moments[0].assetIDs.prefix(6).forEach { store.setFavorite(.memory, $0, isFavorite: true) }
        let model = StoryMakerModel(source: .favorites, library: store.creationLibrary, store: store)
        XCTAssertNil(model.shortfall)
        let aspects = Dictionary(uniqueKeysWithValues: repository.assets.map { ($0.id, $0.aspectRatio ?? 1) })
        let ids = model.cards.indices.map { "relive-story-\($0)" }
        let controller = ExportController(saver: FakeCreationSaver(identifiers: ids))
        await controller.save(store: store, analytics: InMemoryAnalyticsTracker(), properties: [:], onSaved: model.markExported) {
            try await model.renderExport(cardIDs: model.cards.map(\.id), using: CreationImageSource(loader: SolidPhotos(aspects: aspects)))
        }
        XCTAssertEqual(store.createdAssetIDs, Set(ids))
        XCTAssertEqual(store.savedCreations.first?.kind, .story)
        XCTAssertEqual(store.savedCreations.first?.source, .favorites)
    }
}

/// Every photo loads except one, which is gone.
final class SolidPhotosExcept: CreationPhotoLoading, @unchecked Sendable {
    let gone: AssetID
    let solid: SolidPhotos

    init(_ gone: AssetID, aspects: [AssetID: Double]) {
        self.gone = gone
        solid = SolidPhotos(aspects: aspects)
    }

    func image(for id: AssetID, pixelSize: CGSize, contentMode: PHImageContentMode, caches: Bool) async -> UIImage? {
        id == gone ? nil : await solid.image(for: id, pixelSize: pixelSize, contentMode: contentMode, caches: caches)
    }
}
