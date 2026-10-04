import Photos
import ReliveCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import Relive

// v0.3: Memory Book and Trends, in the app. Like the other hosted tests, these never touch
// PhotoKit (see CreationTests): images come from stand-in loaders.

@MainActor
final class MemoryBookStoreTests: XCTestCase {
    func testBooksAreSavedReopenedAndDeleted() throws {
        let (store, repository) = CreationTestLibrary.makeStore()
        let trip = store.story.moments[0]
        let book = try MemoryBookBuilder(library: store.creationLibrary).makeBook(from: .moment(trip.id), now: Date()).get()
        store.saveBook(book)
        XCTAssertEqual(store.books.map(\.id), [book.id])
        XCTAssertEqual(repository.books[book.id]?.photoIDs, book.photoIDs, "the definition is persisted")

        // Reopen: a new store over the same storage finds the book.
        let reopened = StoryStore(
            repository: repository,
            photoLibrary: FakePhotoLibrary(assets: Array(store.assets.values)),
            analyzer: InstantAnalyzer(),
            placeResolver: NoPlaceLookups(),
            analytics: InMemoryAnalyticsTracker()
        )
        let found = try XCTUnwrap(reopened.book(id: book.id))
        XCTAssertEqual(found.photoIDs, book.photoIDs)
        XCTAssertEqual(found.source, book.source)

        // Edits are saved and the most recent book comes first.
        var edited = found
        edited.style = .film
        edited.setNote("For us")
        let second = try MemoryBookBuilder(library: store.creationLibrary).makeBook(from: .photos(Array(trip.assetIDs.prefix(6))), now: Date()).get()
        reopened.saveBook(second)
        reopened.saveBook(edited)
        XCTAssertEqual(reopened.books.map(\.id), [book.id, second.id])
        XCTAssertEqual(repository.books[book.id]?.style, .film)
        XCTAssertEqual(repository.books[book.id]?.note, "For us")

        reopened.deleteBook(id: second.id)
        XCTAssertNil(repository.books[second.id])

        // v0.4: Start Over resets the relationship story, not what the couple made.
        reopened.resetAll()
        XCTAssertEqual(reopened.books.map(\.id), [book.id], "Start Over keeps books")
        XCTAssertNotNil(repository.books[book.id])
        // The book still describes and lays out its photos from its own snapshots.
        let kept = try XCTUnwrap(reopened.book(id: book.id))
        XCTAssertEqual(Set(kept.photoLibraryAssets.map(\.id)), Set(book.photoIDs), "every photo has a metadata snapshot")
        let layout = BookLayoutEngine(library: reopened.creationLibrary(for: kept)).layout(kept)
        XCTAssertTrue(layout.missingAssetIDs.isEmpty)
        XCTAssertEqual(Set(layout.pages.flatMap(\.photoIDs)), Set(book.photoIDs))
    }

    /// Books hold references, never pixels; a missing photo drops out instead of breaking the book.
    func testMissingPhotosDropOutOfSavedBooks() throws {
        let (store, _) = CreationTestLibrary.makeStore()
        let trip = store.story.moments[0]
        let book = try MemoryBookBuilder(library: store.creationLibrary).makeBook(from: .moment(trip.id), now: Date()).get()
        var library = store.creationLibrary
        library.unavailableAssetIDs = [book.photoIDs[1]]
        let layout = BookLayoutEngine(library: library).layout(book)
        XCTAssertEqual(layout.missingAssetIDs, [book.photoIDs[1]])
        XCTAssertFalse(layout.pages.flatMap(\.photoIDs).contains(book.photoIDs[1]))
    }
}

/// Opens a v0.2-shaped store on disk with the v0.3 schema and checks nothing is lost.
@MainActor
final class PersistenceMigrationTests: XCTestCase {
    func testV02StoreOpensWithV03Schema() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "relive-migration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Relive.store")

        // v0.2: everything except Memory Books.
        let v02 = Schema([StoredProfile.self, StoredAsset.self, StoredStorySnapshot.self, StoredMomentState.self, StoredCreatedAsset.self])
        let momentID = UUID()
        do {
            let container = try ModelContainer(for: v02, configurations: [ModelConfiguration(schema: v02, url: url)])
            let repository = SwiftDataStoryRepository(container: container)
            var profile = AppProfile()
            profile.relationship = RelationshipProfile(partnerName: "Emma", userName: "Jake")
            profile.storyRevealedAt = Date(timeIntervalSince1970: 1_700_000_000)
            profile.surprise = SurpriseRecord(momentID: momentID, assetID: "a", day: Date(timeIntervalSince1970: 1_700_000_000), isDismissed: true)
            repository.saveProfile(profile)
            repository.saveAssets([MemoryAsset(localIdentifier: "a", creationDate: Date(), pixelWidth: 10, pixelHeight: 10)])
            repository.saveMomentState(MomentUserState(note: "The boat", isHidden: true), for: momentID)
            repository.recordCreatedAssets(["collage-1"])
        }

        // v0.3 opens the same file.
        let v03 = Schema(PersistenceSchema.models)
        let container = try ModelContainer(for: v03, configurations: [ModelConfiguration(schema: v03, url: url)])
        let repository = SwiftDataStoryRepository(container: container)
        let profile = repository.loadProfile()
        XCTAssertEqual(profile.relationship?.coupleDisplayName, "Jake + Emma")
        XCTAssertNotNil(profile.storyRevealedAt)
        XCTAssertEqual(profile.surprise?.isDismissed, true)
        XCTAssertEqual(repository.loadAssets().map(\.id), ["a"])
        XCTAssertEqual(repository.loadMomentStates()[momentID]?.note, "The boat")
        XCTAssertEqual(repository.loadMomentStates()[momentID]?.isHidden, true)
        XCTAssertEqual(repository.loadCreatedAssetIDs(), ["collage-1"])
        XCTAssertTrue(repository.loadBooks().isEmpty)

        // And books can now be stored.
        let book = MemoryBook(createdAt: Date(), source: .moment(momentID), photoIDs: ["a", "b", "c", "d"])
        repository.saveBook(book)
        XCTAssertEqual(repository.loadBooks().map(\.id), [book.id])
        var changed = book
        changed.style = .editorial
        repository.saveBook(changed)
        XCTAssertEqual(repository.loadBooks().count, 1)
        XCTAssertEqual(repository.loadBooks().first?.style, .editorial)
        repository.deleteBook(id: book.id)
        XCTAssertTrue(repository.loadBooks().isEmpty)
    }

    /// v0.3.1 → v0.4: the same file gains favorites and saved creations; books, the story and
    /// the list of Relive-made images (the export exclusion) come through untouched.
    func testV031StoreOpensWithV04Schema() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "relive-migration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Relive.store")

        // v0.3.1: everything except favorites and saved creations.
        let v031 = Schema([StoredProfile.self, StoredAsset.self, StoredStorySnapshot.self, StoredMomentState.self, StoredCreatedAsset.self, StoredMemoryBook.self])
        let momentID = UUID()
        let library = MemoryAsset(localIdentifier: "library-1", creationDate: Date(timeIntervalSince1970: 1_690_000_000), pixelWidth: 30, pixelHeight: 40)
        let book = MemoryBook(createdAt: Date(timeIntervalSince1970: 1_700_000_000), source: .moment(momentID), style: .film, photoIDs: ["a", "b", "c", "d", "e", "library-1"], photoLibraryAssets: [library])
        do {
            let container = try ModelContainer(for: v031, configurations: [ModelConfiguration(schema: v031, url: url)])
            let repository = SwiftDataStoryRepository(container: container)
            var profile = AppProfile()
            profile.relationship = RelationshipProfile(partnerName: "Emma", userName: "Jake")
            repository.saveProfile(profile)
            repository.saveAssets([MemoryAsset(localIdentifier: "a", creationDate: Date(), pixelWidth: 10, pixelHeight: 10)])
            repository.saveMomentState(MomentUserState(note: "The boat"), for: momentID)
            repository.recordCreatedAssets(["collage-1", "story-1"])
            repository.saveBook(book)
        }

        // v0.4 opens the same file: nothing is lost, nothing needs reinstalling.
        let v04 = Schema(PersistenceSchema.models)
        let container = try ModelContainer(for: v04, configurations: [ModelConfiguration(schema: v04, url: url)])
        let repository = SwiftDataStoryRepository(container: container)
        XCTAssertEqual(repository.loadProfile().relationship?.coupleDisplayName, "Jake + Emma")
        XCTAssertEqual(repository.loadAssets().map(\.id), ["a"])
        XCTAssertEqual(repository.loadMomentStates()[momentID]?.note, "The boat")
        XCTAssertEqual(repository.loadCreatedAssetIDs(), ["collage-1", "story-1"], "exports stay excluded from import")
        let migrated = try XCTUnwrap(repository.loadBooks().first)
        XCTAssertEqual(migrated, book, "the v0.3.1 book opens unchanged")
        XCTAssertTrue(repository.loadFavorites().isEmpty)
        XCTAssertTrue(repository.loadCreations().isEmpty)

        // Favorites and creations can now be stored, without duplicates.
        let favorite = FavoriteRecord(kind: .moment, identifier: momentID.uuidString, favoritedAt: Date(timeIntervalSince1970: 1_700_000_100))
        repository.saveFavorite(favorite)
        repository.saveFavorite(favorite)
        XCTAssertEqual(repository.loadFavorites(), [favorite])
        var creation = SavedCreation(kind: .collage, createdAt: Date(timeIntervalSince1970: 1_700_000_200), source: .moment(momentID), collage: CollageState(photoIDs: ["a", "b"], style: .film, aspectRatio: .square))
        repository.saveCreation(creation)
        creation.markSaved(at: Date(timeIntervalSince1970: 1_700_000_300))
        repository.saveCreation(creation)
        XCTAssertEqual(repository.loadCreations(), [creation], "a finished draft is the same record")

        // Start Over keeps what the couple made and chose.
        repository.deleteAll()
        XCTAssertNil(repository.loadProfile().relationship)
        XCTAssertTrue(repository.loadAssets().isEmpty)
        XCTAssertEqual(repository.loadBooks().map(\.id), [book.id])
        XCTAssertEqual(repository.loadCreations().map(\.id), [creation.id])
        XCTAssertEqual(repository.loadFavorites(), [favorite])
        XCTAssertEqual(repository.loadCreatedAssetIDs(), ["collage-1", "story-1"])
    }
}

@MainActor
final class MemoryBookRenderingTests: XCTestCase {
    private func makeBook() throws -> (MemoryBook, StoryStore) {
        let (store, _) = CreationTestLibrary.makeStore()
        var book = try MemoryBookBuilder(library: store.creationLibrary).makeBook(from: .year(2025), now: Date()).get()
        book.note = "For us."
        return (book, store)
    }

    private func layout() throws -> (BookLayout, StoryStore) {
        let (book, store) = try makeBook()
        return (BookLayoutEngine(library: store.creationLibrary).layout(book), store)
    }

    func testEveryPageKindRendersAtExportSizeInEveryStyle() throws {
        let (initial, store) = try makeBook()
        var book = initial
        var images: CanvasImages = [:]
        for id in book.photoIDs {
            let aspect = store.assets[id]?.aspectRatio ?? 1
            images[id] = TrendTestImages.gradient(width: (300 * aspect).rounded(), height: 300)
        }
        for style in BookStyle.allCases {
            // As in the reader: laid out for the book's own style.
            book.style = style
            let layout = BookLayoutEngine(library: store.creationLibrary).layout(book)
            XCTAssertTrue(Set(layout.pages.map(\.kind)).isSuperset(of: [.cover, .bookNote, .opener, .photos, .closing]))
            var attached = Set<String>()
            for page in layout.pages {
                let canvas = BookPageCanvas(page: page, style: style, images: images)
                let image = try XCTUnwrap(CreationRenderer.render(canvas, size: BookPageCanvas.size), "\(style) \(page.kind)")
                let rendered = try XCTUnwrap(image.cgImage)
                XCTAssertEqual(rendered.width, 2160)
                XCTAssertEqual(rendered.height, 2700)
                // One of each kind (and of each photo template) per style, for review in CI.
                let name = "P-\(style)-\(page.kind)" + (page.template.map { "-\($0)" } ?? "")
                if attached.insert(name).inserted { attach(image, name: name) }
            }
        }
    }

    func testPageExportLoadsEachPhotoAtItsFrameSize() async throws {
        let (layout, store) = try layout()
        let page = try XCTUnwrap(layout.pages.first { $0.kind == .photos && $0.slots.count >= 2 })
        let photos = SolidPhotos(aspects: Dictionary(uniqueKeysWithValues: page.photoIDs.map { ($0, store.assets[$0]?.aspectRatio ?? 1) }))
        let image = try await MemoryBookExport.render(page, style: .classic, using: CreationImageSource(loader: photos))
        XCTAssertEqual(image.cgImage?.width, 2160)
        for request in photos.requests {
            let slot = try XCTUnwrap(page.slots.first { $0.assetID == request.id })
            XCTAssertEqual(request.size, CreationImageSizing.exportPixelSize(forFrame: slot.frame.size).cgSize)
        }

        do {
            _ = try await MemoryBookExport.render(page, style: .classic, using: CreationImageSource(loader: MissingPhotos()))
            XCTFail("Missing photos can't be exported")
        } catch let error as CreationExportError {
            XCTAssertEqual(error, .missingPhotos(page.slots.count))
        }
    }

    func testPagesDescribeThemselvesForVoiceOver() throws {
        let (layout, _) = try layout()
        let cover = BookPageText.accessibilityDescription(of: layout.pages[0], total: layout.pages.count)
        XCTAssertTrue(cover.hasPrefix("Cover"))
        let opener = try XCTUnwrap(layout.pages.first { $0.kind == .opener })
        let description = BookPageText.accessibilityDescription(of: opener, total: layout.pages.count)
        XCTAssertTrue(description.contains("Page \(opener.id + 1) of \(layout.pages.count)"))
        XCTAssertTrue(description.contains("photo"))
    }
}

@MainActor
final class TrendAppTests: XCTestCase {
    func testEveryBundledOnDeviceTrendHasARecipeInThisApp() {
        for trend in StarterTrendCatalog.catalog.trends where trend.execution != .ai {
            XCTAssertNotNil(TrendRecipeRegistry.recipe(for: trend.recipe), trend.id)
        }
        let store = TrendCatalogStore(remote: nil, appVersion: AppVersion("0.3"))
        let visible = store.visibleTrends()
        XCTAssertEqual(visible.filter { $0.availability == .available }.count, 5)
        XCTAssertEqual(visible.filter { $0.availability == .comingSoon }.map(\.trend.id), ["golden-hour-portrait"])
        XCTAssertEqual(visible.first?.trend.id, "bw-editorial", "highest priority first")
    }

    func testEveryRecipeRendersEachVariationAtExportSize() async throws {
        let photo = TrendTestImages.gradient(width: 600, height: 800)
        for recipe in TrendRecipeRegistry.all {
            for variation in recipe.variations.indices {
                let processed = await recipe.process(photo, variation: variation)
                XCTAssertEqual(processed.size.width / processed.size.height, 0.75, accuracy: 0.01, "\(recipe.reference)")
                let photos = (0..<4).map { TrendPhoto(assetID: "p\($0)", image: processed, date: Date()) }
                let context = TrendRenderContext(facts: CreationFacts(title: .named("Kaş"), place: PlaceName(name: "Kaş")), coupleNames: "Jake & Emma", variation: variation)
                let image = try XCTUnwrap(CreationRenderer.render(recipe.canvas(photos: photos, context: context), size: recipe.designSize))
                let rendered = try XCTUnwrap(image.cgImage)
                XCTAssertEqual(rendered.width, recipe.aspectRatio.exportPixelSize.width, "\(recipe.reference)")
                XCTAssertEqual(rendered.height, recipe.aspectRatio.exportPixelSize.height, "\(recipe.reference)")
                if variation == 0 { attach(image, name: "R-\(recipe.reference.id)") }
            }
        }
    }

    /// Processing must keep a photo's mid-tones: a neutral grey stays a visible grey in every
    /// recipe and variation (never crushed to black or blown out to white).
    func testProcessingKeepsMidTones() async throws {
        let grey = TrendTestImages.solid(white: 0.5, width: 400, height: 500)
        for recipe in TrendRecipeRegistry.all {
            for variation in recipe.variations.indices {
                let processed = await recipe.process(grey, variation: variation)
                let level = try XCTUnwrap(TrendTestImages.centreLuminance(of: processed))
                XCTAssertTrue((0.2...0.85).contains(level), "\(recipe.reference) \(recipe.variations[variation]): \(level)")
            }
        }
    }

    func testLocalProcessingIsDeterministic() async throws {
        let photo = CreationTestLibrary.solidImage(width: 400, height: 500)
        for recipe in TrendRecipeRegistry.all {
            let first = await recipe.process(photo, variation: 0).pngData()
            let second = await recipe.process(photo, variation: 0).pngData()
            XCTAssertEqual(first, second, "\(recipe.reference)")
        }
    }

    func testStudioPreviewsAndExportsChosenPhotos() async throws {
        let (store, _) = CreationTestLibrary.makeStore()
        let trend = try XCTUnwrap(StarterTrendCatalog.catalog.trends.first { $0.id == "photo-booth-strip" })
        let recipe = try XCTUnwrap(TrendRecipeRegistry.recipe(for: trend.recipe))
        let ids = Array(store.story.moments[0].assetIDs.prefix(4))
        let model = TrendStudioModel(trend: trend, recipe: recipe, photoIDs: ids, library: store.creationLibrary, coupleNames: nil)
        let photos = SolidPhotos(aspects: Dictionary(uniqueKeysWithValues: ids.map { ($0, store.assets[$0]?.aspectRatio ?? 1) }))
        await model.load(using: CreationImageSource(loader: photos))
        XCTAssertEqual(model.processed.count, 4)
        XCTAssertTrue(model.canExport)
        XCTAssertEqual(model.facts.title, .named("Kaş"))

        await model.choose(variation: 1)
        XCTAssertEqual(model.variation, 1)
        let image = try await model.renderExport(using: CreationImageSource(loader: photos), dates: [:])
        XCTAssertEqual(image.cgImage?.width, 2160)
        XCTAssertEqual(image.cgImage?.height, 3840)

        let gone = TrendStudioModel(trend: trend, recipe: recipe, photoIDs: ids, library: store.creationLibrary, coupleNames: nil)
        await gone.load(using: CreationImageSource(loader: MissingPhotos()))
        XCTAssertFalse(gone.canExport)
    }

    func testAITrendIsHonestlyUnavailableAndDisclosed() throws {
        let store = TrendCatalogStore(remote: nil, appVersion: AppVersion("0.3"))
        let ai = try XCTUnwrap(store.trend(id: "golden-hour-portrait"))
        let availability = TrendCatalogFilter.availability(of: ai, in: store.context())
        XCTAssertEqual(availability, .comingSoon)
        XCTAssertEqual(TrendFlowPolicy.primaryAction(for: ai, availability: availability), .unavailable("Not available yet"))
        XCTAssertTrue(TrendFlowPolicy.needsDisclosure(ai))
        XCTAssertFalse(store.ai.isAvailable, "no AI provider ships in this version")
        XCTAssertNil(TrendRecipeRegistry.recipe(for: ai.recipe), "AI recipes never run on the iPhone")

        let local = try XCTUnwrap(store.trend(id: "bw-editorial"))
        XCTAssertFalse(TrendFlowPolicy.needsDisclosure(local))
        XCTAssertEqual(TrendFlowPolicy.primaryAction(for: local, availability: .available), .choosePhotos)
        XCTAssertTrue(TrendFlowPolicy.privacyLine(for: local).contains("on this iPhone"))
    }

    func testCatalogFallsBackAndUpgradesSafely() async {
        let newer = TrendCatalog(revision: 99, trends: [StarterTrendCatalog.catalog.trends[0]])
        let fetching = StubCatalogProvider(cached: nil, fetched: newer)
        let store = TrendCatalogStore(remote: fetching, appVersion: AppVersion("0.3"))
        XCTAssertEqual(store.catalog, StarterTrendCatalog.catalog, "before refreshing: the bundled catalog")
        await store.refresh()
        XCTAssertEqual(store.catalog.revision, 99)

        let offline = TrendCatalogStore(remote: StubCatalogProvider(cached: nil, fetched: nil), appVersion: AppVersion("0.3"))
        await offline.refresh()
        XCTAssertEqual(offline.catalog, StarterTrendCatalog.catalog)

        let cached = TrendCatalogStore(remote: StubCatalogProvider(cached: newer, fetched: nil), appVersion: AppVersion("0.3"))
        XCTAssertEqual(cached.catalog.revision, 99, "a previously downloaded catalog is used offline")
    }

    func testRemoteProviderOnlyAcceptsHTTPS() {
        XCTAssertNil(RemoteTrendCatalogProvider(url: URL(string: "http://example.com/catalog.json")!))
        XCTAssertNotNil(RemoteTrendCatalogProvider(url: URL(string: "https://example.com/catalog.json")!))
        XCTAssertNil(RemoteTrendCatalogProvider.configured(bundle: .main), "no remote catalog is configured in this build")
    }
}

/// Test photos in plain 8-bit sRGB, like library photos.
enum TrendTestImages {
    private static var format: UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        return format
    }

    /// A warm-to-cool vertical gradient, so tonal processing shows in renders.
    nonisolated static func gradient(width: CGFloat, height: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            let colours = [
                UIColor(red: 0.98, green: 0.86, blue: 0.66, alpha: 1).cgColor,
                UIColor(red: 0.78, green: 0.52, blue: 0.42, alpha: 1).cgColor,
                UIColor(red: 0.22, green: 0.3, blue: 0.42, alpha: 1).cgColor,
            ] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colours, locations: [0, 0.55, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])
        }
    }

    nonisolated static func solid(white: CGFloat, width: CGFloat, height: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor(white: white, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// The luminance (0…1) of a small patch at the centre of `image`.
    static func centreLuminance(of image: UIImage) -> Double? {
        guard let cgImage = image.cgImage else { return nil }
        let side = 8
        let patch = CGRect(x: cgImage.width / 2 - side / 2, y: cgImage.height / 2 - side / 2, width: side, height: side)
        guard let cropped = cgImage.cropping(to: patch) else { return nil }
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        var total = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            total += 0.2126 * Double(pixels[index]) + 0.7152 * Double(pixels[index + 1]) + 0.0722 * Double(pixels[index + 2])
        }
        return total / Double(side * side) / 255
    }
}

extension XCTestCase {
    /// Keeps a rendered image with the test result, for visual review (CI prints thumbnails).
    func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

struct StubCatalogProvider: TrendCatalogProviding {
    let cached: TrendCatalog?
    let fetched: TrendCatalog?

    func cachedCatalog() -> TrendCatalog? { cached }
    func fetchCatalog() async -> TrendCatalog? { fetched }
}
