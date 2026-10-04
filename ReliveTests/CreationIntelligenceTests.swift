import ReliveCore
import SwiftUI
import UIKit
import XCTest
@testable import Relive

// v0.3.1: photos from the photo library, metadata that follows the photo, Story Maker 2.0.
// Like the other hosted tests, these never touch PhotoKit: the "library" is a test double.

@MainActor
enum PhotoLibraryTestStore {
    static let calendar = Calendar.current

    /// Photos in the iPhone library that are not memories: different months, one with a place.
    static let libraryPhotos: [MemoryAsset] = [
        MemoryAsset(
            localIdentifier: "lib-aug", creationDate: date(2026, 8, 30, 19),
            location: GeoCoordinate(latitude: 38.7996, longitude: 26.9707), pixelWidth: 3024, pixelHeight: 4032
        ),
        MemoryAsset(localIdentifier: "lib-sep", creationDate: date(2026, 9, 5, 19), pixelWidth: 4032, pixelHeight: 3024),
        MemoryAsset(localIdentifier: "lib-oct", creationDate: date(2026, 10, 2, 19), pixelWidth: 3024, pixelHeight: 4032),
        MemoryAsset(localIdentifier: "lib-video", creationDate: date(2026, 9, 6), kind: .video),
    ]

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// The creation test story, with a photo library that also holds `libraryPhotos`.
    static func make() -> (StoryStore, InMemoryStoryRepository) {
        let (story, assets) = CreationTestLibrary.makeStory()
        let repository = InMemoryStoryRepository(assets: assets)
        repository.story = story
        let store = StoryStore(
            repository: repository,
            photoLibrary: FakePhotoLibrary(assets: assets + libraryPhotos),
            analyzer: InstantAnalyzer(),
            placeResolver: NoPlaceLookups(),
            analytics: InMemoryAnalyticsTracker()
        )
        return (store, repository)
    }
}

@MainActor
final class PhotoLibraryPickTests: XCTestCase {
    func testPicksKeepTheirOwnMetadataAndNeverJoinTheStory() async {
        let (store, repository) = PhotoLibraryTestStore.make()
        let storyBefore = store.story
        let assetsBefore = store.assets

        let picks = await store.resolvePhotoLibraryPicks(["lib-aug", "trip-1", "lib-oct", "lib-video", "not-shared", "lib-aug"])
        XCTAssertEqual(picks.ids, ["lib-aug", "trip-1", "lib-oct"], "pick order kept; videos and duplicates left out")
        XCTAssertEqual(picks.unavailableCount, 1, "a photo Relive can't read is counted, not guessed")
        XCTAssertEqual(picks.libraryAssets.map(\.id), ["lib-aug", "lib-oct"], "a memory keeps its memory metadata")

        let august = try? XCTUnwrap(picks.libraryAssets.first)
        XCTAssertEqual(august?.creationDate, PhotoLibraryTestStore.date(2026, 8, 30, 19))
        XCTAssertEqual(august?.location, GeoCoordinate(latitude: 38.7996, longitude: 26.9707))
        XCTAssertEqual(august?.pixelWidth, 3024)

        XCTAssertEqual(store.story, storyBefore, "nothing is imported into the story")
        XCTAssertEqual(store.assets, assetsBefore)
        XCTAssertEqual(repository.assets.count, assetsBefore.count)
    }

    func testCreationAssetsFromTheLibraryDescribeThemselves() async {
        let (store, _) = PhotoLibraryTestStore.make()
        let picks = await store.resolvePhotoLibraryPicks(["lib-aug", "lib-sep", "lib-oct"])
        let library = store.creationLibrary.addingPhotoLibraryAssets(picks.libraryAssets)
        let asset = library.creationAsset("lib-aug")
        XCTAssertEqual(asset?.source, .photoLibrary)
        XCTAssertEqual(asset?.creationDate, PhotoLibraryTestStore.date(2026, 8, 30, 19))
        XCTAssertNil(asset?.place, "no place name is looked up for a creation")
        let facts = library.facts(forPhotos: picks.ids)
        XCTAssertEqual(facts.title, .year(2026), "August to October is not September")
        XCTAssertNil(facts.place)
    }

    func testABookOfLibraryPhotosSurvivesARestart() async throws {
        let (store, repository) = PhotoLibraryTestStore.make()
        let picks = await store.resolvePhotoLibraryPicks(["lib-aug", "lib-sep", "lib-oct"])
        let library = store.creationLibrary.addingPhotoLibraryAssets(picks.libraryAssets)
        let chosen = picks.ids + ["trip-0", "trip-1", "trip-2"]
        let book = try MemoryBookBuilder(library: library).makeBook(from: .photos(chosen), now: Date()).get()
        store.saveBook(book)

        let reopened = StoryStore(
            repository: repository,
            photoLibrary: FakePhotoLibrary(assets: Array(store.assets.values) + PhotoLibraryTestStore.libraryPhotos),
            analyzer: InstantAnalyzer(),
            placeResolver: NoPlaceLookups(),
            analytics: InMemoryAnalyticsTracker()
        )
        let saved = try XCTUnwrap(reopened.book(id: book.id))
        let layout = BookLayoutEngine(library: reopened.creationLibrary(for: saved)).layout(saved)
        XCTAssertEqual(Set(layout.photoIDs), Set(chosen))
        XCTAssertTrue(layout.missingAssetIDs.isEmpty)
        XCTAssertNotEqual(layout.facts.title, .month(MonthKey(year: 2026, month: 9)))

        // A library photo deleted later drops out like a memory would.
        let gone = StoryStore(
            repository: repository,
            photoLibrary: FakePhotoLibrary(assets: Array(store.assets.values) + PhotoLibraryTestStore.libraryPhotos.filter { $0.id != "lib-sep" }),
            analyzer: InstantAnalyzer(),
            placeResolver: NoPlaceLookups(),
            analytics: InMemoryAnalyticsTracker()
        )
        await gone.refreshAvailability()
        let afterDeletion = try XCTUnwrap(gone.book(id: book.id))
        XCTAssertEqual(BookLayoutEngine(library: gone.creationLibrary(for: afterDeletion)).layout(afterDeletion).missingAssetIDs, ["lib-sep"])
    }

    func testCollageWithLibraryPhotosIsDescribedByThem() async {
        let (store, _) = PhotoLibraryTestStore.make()
        let model = CollageEditorModel(source: .moment(store.story.moments[0].id), photos: ["trip-0", "trip-1"], library: store.creationLibrary)
        XCTAssertEqual(model.titleText, "Kaş")
        let picks = await store.resolvePhotoLibraryPicks(["lib-oct"])
        model.addPhotoLibraryAssets(picks.libraryAssets)
        model.setPhotos(model.photoIDs + picks.ids)
        XCTAssertNotEqual(model.titleText, "Kaş", "an October photo from elsewhere isn't Kaş")
        XCTAssertNil(model.placeText)
    }
}

@MainActor
final class StoryMaker2Tests: XCTestCase {
    func testRelieveDesignsAStoryAndMakeItForMeDesignsAnother() throws {
        let (store, _) = CreationTestLibrary.makeStore()
        let model = StoryMakerModel(source: .moment(store.story.moments[0].id), library: store.creationLibrary)
        let first = try XCTUnwrap(model.design)
        XCTAssertTrue(StoryDesigner.cardRange.contains(first.cards.count))
        XCTAssertTrue(first.cards.contains { $0.photos.count >= 2 }, "not one photo per card")
        model.makeItForMe()
        let second = try XCTUnwrap(model.design)
        XCTAssertNotEqual(second, first)
        XCTAssertTrue(StoryDesigner.cardRange.contains(second.cards.count))
    }

    func testCardCorrections() throws {
        let (store, _) = CreationTestLibrary.makeStore()
        let model = StoryMakerModel(source: .moment(store.story.moments[0].id), library: store.creationLibrary)
        let opening = try XCTUnwrap(model.cards.first)
        XCTAssertNotNil(StoryCardText(card: opening).subtitle)
        model.toggleDate(of: opening.id)
        XCTAssertNil(StoryCardText(card: try XCTUnwrap(model.cards.first)).subtitle, "Hide Date hides it")
        XCTAssertNotNil(StoryCardText(card: try XCTUnwrap(model.cards.first)).title, "the title stays")

        model.changeLayout(of: opening.id)
        XCTAssertEqual(model.cards.first?.layout, .coverFramed)

        let photoCard = try XCTUnwrap(model.cards.first { $0.role == .photo })
        let before = model.cards.count
        model.removeCard(photoCard.id)
        XCTAssertEqual(model.cards.count, before - 1)
        model.removeCard(opening.id)
        XCTAssertEqual(model.cards.first?.id, opening.id, "the opening stays")
    }

    func testReplacingWithALibraryPhotoUpdatesTheCardsFacts() async throws {
        let (store, _) = PhotoLibraryTestStore.make()
        let model = StoryMakerModel(source: .moment(store.story.moments[0].id), library: store.creationLibrary)
        let card = try XCTUnwrap(model.cards.first { $0.role == .photo })
        let picks = await store.resolvePhotoLibraryPicks(["lib-oct"])
        model.replacePhoto(cardID: card.id, slot: 0, with: "lib-oct", photoLibraryAssets: picks.libraryAssets)
        let edited = try XCTUnwrap(model.cards.first { $0.id == card.id })
        XCTAssertEqual(edited.photos[0], "lib-oct")
        if edited.photos.count == 1 {
            XCTAssertEqual(edited.dateSpan, DateSpan(start: PhotoLibraryTestStore.date(2026, 10, 2, 19), end: PhotoLibraryTestStore.date(2026, 10, 2, 19)))
        }
        XCTAssertNil(edited.place, "the October photo has no known place")
    }

    func testExportRendersEveryCardInOrderWithEachPhotoAtItsFrameSize() async throws {
        let (store, _) = CreationTestLibrary.makeStore()
        let model = StoryMakerModel(source: .moment(store.story.moments[0].id), library: store.creationLibrary)
        let ids = Set(model.design?.photoIDs ?? [])
        let photos = SolidPhotos(aspects: Dictionary(uniqueKeysWithValues: ids.map { ($0, store.assets[$0]?.aspectRatio ?? 1) }))
        let images = try await model.renderExport(cardIDs: model.cards.map(\.id), using: CreationImageSource(loader: photos))
        XCTAssertEqual(images.count, model.cards.count, "Save All saves every card, in order")
        for image in images {
            XCTAssertEqual(image.cgImage?.width, 2160)
            XCTAssertEqual(image.cgImage?.height, 3840)
        }
        for card in model.cards where !card.photos.isEmpty {
            let slots = StoryCardGeometry.slots(for: card, style: model.style, aspects: model.aspects(for: card))
            for (id, slot) in zip(card.photos, slots) {
                let expected = CreationImageSizing.exportPixelSize(forFrame: CanvasSize(width: Double(slot.frame.width), height: Double(slot.frame.height))).cgSize
                XCTAssertTrue(photos.requests.contains { $0.id == id && $0.size == expected }, "\(id) loaded at its frame size")
            }
        }
    }

    func testMissingPhotosAreLeftOutOfExports() async {
        let (store, _) = CreationTestLibrary.makeStore()
        let model = StoryMakerModel(source: .moment(store.story.moments[0].id), library: store.creationLibrary)
        do {
            _ = try await model.renderExport(cardIDs: model.cards.map(\.id), using: CreationImageSource(loader: MissingPhotos()))
            XCTFail("Missing photos can't be exported")
        } catch {
            XCTAssertTrue(error is CreationExportError)
        }
    }

    /// Every layout in every style renders at export size; one of each is attached for review.
    func testEveryLayoutRendersInEveryStyle() throws {
        let images: CanvasImages = [
            "p": CreationTestLibrary.solidImage(width: 300, height: 400),
            "l": CreationTestLibrary.solidImage(width: 400, height: 300),
            "q": CreationTestLibrary.solidImage(width: 300, height: 400),
        ]
        let day = DateSpan(start: Date(), end: Date())
        for style in StoryStyle.allCases {
            for layout in StoryLayout.allCases {
                let photos = Array(["p", "l", "q"].prefix(layout.photoCount))
                let role: StoryCardRole
                switch layout {
                case .cover, .coverFramed: role = .opening
                case .caption: role = .place
                case .closing: role = .closing
                default: role = .photo
                }
                let card = StoryCard(
                    id: 1, role: role, layout: layout, photos: photos, title: .named("Aliağa"), dateSpan: day,
                    place: PlaceName(name: "Aliağa"), coordinate: GeoCoordinate(latitude: 38.8, longitude: 26.97), showsCoordinates: true
                )
                let aspects = photos.map { $0 == "l" ? 4.0 / 3.0 : 0.75 }
                let canvas = StoryCardCanvas(card: card, style: style, images: images, aspects: aspects, number: 2)
                let image = try XCTUnwrap(CreationRenderer.render(canvas, size: StoryCardCanvas.size), "\(style) \(layout)")
                XCTAssertEqual(image.cgImage?.width, 2160)
                XCTAssertEqual(image.cgImage?.height, 3840)
                if [.cover, .duoOffset, .trioStrip, .postcard].contains(layout) {
                    attach(image, name: "S-\(style.rawValue)-\(layout.rawValue)")
                }
            }
        }
    }

    func testCardTextNeverInventsAnything() {
        let card = StoryCard(id: 0, role: .opening, layout: .cover, photos: ["a"])
        let text = StoryCardText(card: card)
        XCTAssertEqual(text.title, "Our Memories", "no name, no dates: a neutral headline")
        XCTAssertNil(text.subtitle)
        XCTAssertNil(text.meta)
        XCTAssertNil(text.coordinate)
        XCTAssertNil(text.stamp)
        let closing = StoryCardText(card: StoryCard(id: 1, role: .closing, layout: .closing, photos: []))
        XCTAssertNil(closing.title, "nothing known, nothing said")
    }
}
