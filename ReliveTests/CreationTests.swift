import Photos
import ReliveCore
import SwiftUI
import UIKit
import XCTest
@testable import Relive

/// A small story for creation tests: a trip moment a year before `CreationTests.now`, an evening
/// in the same month, and a small two-photo moment.
@MainActor
enum CreationTestLibrary {
    static let calendar = Calendar.current
    static let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 7, hour: 10))!

    static func makeStory() -> (Story, [MemoryAsset]) {
        var assets: [MemoryAsset] = []
        var moments: [Moment] = []
        func add(_ key: String, start: Date, count: Int, width: Int, height: Int, place: String?) {
            let members = (0..<count).map { index in
                MemoryAsset(
                    localIdentifier: "\(key)-\(index)",
                    creationDate: start.addingTimeInterval(Double(index) * 900),
                    pixelWidth: index.isMultiple(of: 3) ? height : width,
                    pixelHeight: index.isMultiple(of: 3) ? width : height
                )
            }
            assets += members
            moments.append(Moment(
                id: UUID(),
                kind: .event,
                assetIDs: members.map(\.id),
                featuredAssetIDs: members.map(\.id),
                heroAssetID: members.first?.id,
                startDate: start,
                endDate: start.addingTimeInterval(Double(count) * 900),
                centroid: place == nil ? nil : GeoCoordinate(latitude: 36.2, longitude: 29.64),
                place: place.map { PlaceName(name: $0) },
                title: MomentTitle(primary: place ?? "Summer Evening")
            ))
        }
        let yearAgo = calendar.date(byAdding: .year, value: -1, to: now)!
        add("trip", start: yearAgo, count: 9, width: 3024, height: 4032, place: "Kaş")
        add("evening", start: calendar.date(byAdding: .day, value: 12, to: yearAgo)!, count: 5, width: 4032, height: 3024, place: nil)
        add("small", start: calendar.date(byAdding: .month, value: -3, to: now)!, count: 2, width: 3024, height: 4032, place: nil)
        return (Story(generatedAt: now, moments: moments, chapters: []), assets)
    }

    static func makeStore() -> (StoryStore, InMemoryStoryRepository) {
        let (story, assets) = makeStory()
        let repository = InMemoryStoryRepository(assets: assets)
        repository.story = story
        let store = StoryStore(
            repository: repository,
            photoLibrary: FakePhotoLibrary(assets: assets),
            analyzer: InstantAnalyzer(),
            placeResolver: NoPlaceLookups(),
            analytics: InMemoryAnalyticsTracker()
        )
        return (store, repository)
    }

    nonisolated static func solidImage(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
}

@MainActor
final class CreationRenderingTests: XCTestCase {
    /// The export is exactly the advertised size for every shape and style.
    func testCollageExportSizeMatchesEachShape() throws {
        let ids = ["a", "b", "c"]
        let images: CanvasImages = [
            "a": CreationTestLibrary.solidImage(width: 300, height: 400),
            "b": CreationTestLibrary.solidImage(width: 400, height: 300),
            "c": CreationTestLibrary.solidImage(width: 300, height: 300),
        ]
        for ratio in CreationAspectRatio.allCases {
            for style in CollageStyle.allCases {
                let layout = CollageLayoutEngine().layout(
                    photoAspects: [0.75, 1.33, 1], style: style, canvas: ratio.designSize,
                    caption: CollageCaptionSpec(showsTitle: true, showsDetail: true)
                )
                let canvas = CollageCanvas(layout: layout, photoIDs: ids, images: images, caption: CaptionContent(title: "Kaş", detail: "August 6, 2025"))
                let rendered = try XCTUnwrap(CreationRenderer.render(canvas, size: layout.canvas), "\(style) \(ratio)")
                let cgImage = try XCTUnwrap(rendered.cgImage)
                XCTAssertEqual(cgImage.width, ratio.exportPixelSize.width, "\(style) \(ratio)")
                XCTAssertEqual(cgImage.height, ratio.exportPixelSize.height, "\(style) \(ratio)")
            }
        }
    }

    func testStoryAndSummaryCardsRenderAtExportSize() throws {
        let card = StoryCardPlan(id: 0, kind: .opening, assetID: "a", title: .named("Kaş"), dateSpan: DateSpan(start: Date(), end: Date()))
        for style in StoryStyle.allCases {
            let canvas = StoryCardCanvas(card: card, style: style, image: CreationTestLibrary.solidImage(width: 300, height: 400))
            let image = try XCTUnwrap(CreationRenderer.render(canvas, size: StoryCardCanvas.size)?.cgImage)
            XCTAssertEqual(image.width, 2160)
            XCTAssertEqual(image.height, 3840)
        }
        let summary = SummaryCardCanvas(
            eyebrow: "2026", title: "Our 2026", counts: "12 memories", photoIDs: ["a"],
            images: ["a": CreationTestLibrary.solidImage(width: 200, height: 200)],
            mosaic: SummaryCardCanvas.makeMosaic(aspects: [1])
        )
        let image = try XCTUnwrap(CreationRenderer.render(summary, size: SummaryCardCanvas.size)?.cgImage)
        XCTAssertEqual(image.width, 2160)
        XCTAssertEqual(image.height, 2700)
    }

    /// A photo that couldn't be loaded draws a placeholder instead of breaking the render.
    func testRenderingWithMissingImagesStillProducesAnImage() throws {
        let layout = CollageLayoutEngine().layout(photoAspects: [1, 1], style: .polaroid, canvas: CreationAspectRatio.square.designSize, caption: .none)
        let canvas = CollageCanvas(layout: layout, photoIDs: ["gone", "also-gone"], images: [:], missing: ["gone", "also-gone"])
        XCTAssertNotNil(CreationRenderer.render(canvas, size: layout.canvas))
    }
}

@MainActor
final class CollageEditorModelTests: XCTestCase {
    private func makeModel(source: CreationSource? = nil) -> (CollageEditorModel, StoryStore) {
        let (store, _) = CreationTestLibrary.makeStore()
        let library = store.creationLibrary
        let trip = store.story.moments[0]
        let source = source ?? .moment(trip.id)
        let photos = library.initialPhotos(for: source, limit: CreationLimits.collagePreselection)
        return (CollageEditorModel(source: source, photos: photos, library: library), store)
    }

    func testStartsFromTheMomentWithACompleteDesign() {
        let (model, store) = makeModel()
        let trip = store.story.moments[0]
        XCTAssertEqual(model.photoIDs.count, CreationLimits.collagePreselection)
        XCTAssertTrue(Set(model.photoIDs).isSubset(of: Set(trip.assetIDs)))
        XCTAssertEqual(model.titleText, "Kaş")
        XCTAssertNotNil(model.dateText)
        XCTAssertEqual(model.placeText, "Kaş")
        // The place is the title already, so it isn't printed twice.
        XCTAssertEqual(model.caption.title, "Kaş")
        XCTAssertFalse(model.caption.detail?.contains("Kaş") ?? false)
        XCTAssertEqual(model.layout.slots.count, model.photoIDs.count)
        XCTAssertTrue(model.canExport)
    }

    func testMakeItForMeIsDeterministicAndOffersDistinctLooks() {
        let (first, _) = makeModel()
        let (second, _) = makeModel()
        XCTAssertEqual(first.style, second.style)
        XCTAssertEqual(first.aspectRatio, second.aspectRatio)
        XCTAssertEqual(first.photoIDs, second.photoIDs)

        var styles = [first.style]
        first.makeItForMe()
        styles.append(first.style)
        first.makeItForMe()
        styles.append(first.style)
        XCTAssertEqual(Set(styles).count, 3, "three presses, three different looks")
    }

    func testTappingTwoPhotosSwapsThem() {
        let (model, _) = makeModel()
        let original = model.photoIDs
        model.tapPhoto(at: 0)
        XCTAssertEqual(model.selectedIndex, 0)
        model.tapPhoto(at: 2)
        XCTAssertNil(model.selectedIndex)
        XCTAssertEqual(model.photoIDs[0], original[2])
        XCTAssertEqual(model.photoIDs[2], original[0])
        // Tapping the same photo twice just lets go.
        model.tapPhoto(at: 1)
        model.tapPhoto(at: 1)
        XCTAssertNil(model.selectedIndex)
        XCTAssertEqual(model.photoIDs[1], original[1])
    }

    func testEditingPhotosKeepsLimitsAndOrder() {
        let (model, store) = makeModel()
        let trip = store.story.moments[0]
        let unused = trip.assetIDs.first { !model.photoIDs.contains($0) }!

        model.replacePhoto(at: 1, with: unused)
        XCTAssertEqual(model.photoIDs[1], unused)
        model.replacePhoto(at: 2, with: unused)
        XCTAssertNotEqual(model.photoIDs[2], unused, "a photo can't appear twice")

        let kept = Array(model.photoIDs.prefix(2))
        model.setPhotos(kept.reversed() + ["evening-0"])
        XCTAssertEqual(model.photoIDs, kept + ["evening-0"], "kept photos stay in place; new ones join the end")
        XCTAssertNil(model.titleText, "photos from two unrelated moments get no invented title")
        XCTAssertNil(model.placeText)

        model.removePhoto(at: 0)
        model.removePhoto(at: 0)
        XCTAssertEqual(model.photoIDs.count, 2, "a collage keeps at least two photos")
    }

    func testCaptionTogglesChangeTheLayout() {
        let (model, _) = makeModel()
        XCTAssertNotNil(model.layout.caption)
        model.showsTitle = false
        model.showsDate = false
        model.showsPlace = false
        XCTAssertNil(model.layout.caption)
        XCTAssertTrue(model.caption.isEmpty)
    }

    /// Photos that are no longer in the library can't be exported, and say so.
    func testExportFailsGracefullyWhenPhotosAreGone() async {
        let (model, _) = makeModel()
        do {
            _ = try await model.renderExport(using: CreationImageSource(loader: MissingPhotos()))
            XCTFail("Test identifiers don't exist in the photo library")
        } catch let error as CreationExportError {
            XCTAssertEqual(error, .missingPhotos(model.photoIDs.count))
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    /// The exported collage is the previewed layout at export size, and each photo is requested
    /// only at the size its frame needs — never the original.
    func testExportRendersThePreviewedLayoutAtExportSize() async throws {
        let (model, store) = makeModel()
        let photos = SolidPhotos(aspects: Dictionary(uniqueKeysWithValues: model.photoIDs.map { ($0, store.assets[$0]?.aspectRatio ?? 1) }))
        await model.loadPreviews(using: CreationImageSource(loader: photos))
        XCTAssertEqual(model.previewImages.count, model.photoIDs.count)
        let previewLayout = model.layout

        let image = try await model.renderExport(using: CreationImageSource(loader: photos))
        let cgImage = try XCTUnwrap(image.cgImage)
        XCTAssertEqual(cgImage.width, model.aspectRatio.exportPixelSize.width)
        XCTAssertEqual(cgImage.height, model.aspectRatio.exportPixelSize.height)
        XCTAssertEqual(model.layout, previewLayout, "exporting doesn't change the arrangement")

        let exportRequests = photos.requests.suffix(model.photoIDs.count)
        for request in exportRequests {
            let slot = try XCTUnwrap(previewLayout.slots.first { model.photoIDs[$0.photoIndex] == request.id })
            let needed = CreationImageSizing.exportPixelSize(forFrame: slot.photoFrame.size)
            XCTAssertEqual(request.size, needed.cgSize)
            XCTAssertLessThanOrEqual(max(request.size.width, request.size.height), CreationImageSizing.maximumExportSide)
        }
    }

    func testPreviewsMarkMissingPhotosInsteadOfFailing() async {
        let (model, _) = makeModel()
        await model.loadPreviews(using: CreationImageSource(loader: MissingPhotos()))
        XCTAssertEqual(Set(model.missingInCollage), Set(model.photoIDs))
        XCTAssertFalse(model.canExport)
    }
}

/// Every photo is gone from the library.
struct MissingPhotos: CreationPhotoLoading {
    func image(for id: AssetID, pixelSize: CGSize, contentMode: PHImageContentMode, caches: Bool) async -> UIImage? { nil }
}

/// Every photo loads, as a solid image of its own shape at the requested size, and requests
/// are recorded so tests can check what was asked of the library.
final class SolidPhotos: CreationPhotoLoading, @unchecked Sendable {
    let aspects: [AssetID: Double]
    private let lock = NSLock()
    private var log: [(id: AssetID, size: CGSize)] = []

    init(aspects: [AssetID: Double]) {
        self.aspects = aspects
    }

    var requests: [(id: AssetID, size: CGSize)] { lock.withLock { log } }

    func image(for id: AssetID, pixelSize: CGSize, contentMode: PHImageContentMode, caches: Bool) async -> UIImage? {
        lock.withLock { log.append((id, pixelSize)) }
        let aspect = aspects[id] ?? 1
        // Like PhotoKit: keep the photo's shape, cover (fill) or fit inside the requested size.
        let scale = contentMode == .aspectFill
            ? max(pixelSize.width / aspect, pixelSize.height)
            : min(pixelSize.width / aspect, pixelSize.height)
        return CreationTestLibrary.solidImage(width: (scale * aspect).rounded(), height: scale.rounded())
    }
}

@MainActor
final class StoryMakerModelTests: XCTestCase {
    func testBuildsCardsFromAMoment() {
        let (store, _) = CreationTestLibrary.makeStore()
        let trip = store.story.moments[0]
        let model = StoryMakerModel(source: .moment(trip.id), library: store.creationLibrary)
        XCTAssertNil(model.shortfall)
        XCTAssertTrue((3...6).contains(model.cards.count))
        XCTAssertEqual(model.cards.first?.kind, .opening)
        XCTAssertEqual(model.style, .travel, "a moment with a real place starts with the Travel look")
    }

    func testSmallMomentExplainsWhatIsMissing() {
        let (store, _) = CreationTestLibrary.makeStore()
        let small = store.story.moments[2]
        let model = StoryMakerModel(source: .moment(small.id), library: store.creationLibrary)
        XCTAssertEqual(model.shortfall, .notEnoughPhotos(available: 2, required: 3))
        XCTAssertTrue(model.cards.isEmpty)
        XCTAssertEqual(model.style, .minimal)
    }

    /// When the photos can't be loaded, the story is rebuilt without them — here, down to a shortfall.
    func testMissingPhotosAreLeftOut() async {
        let (store, _) = CreationTestLibrary.makeStore()
        let trip = store.story.moments[0]
        let model = StoryMakerModel(source: .moment(trip.id), library: store.creationLibrary)
        await model.loadPreviews(using: CreationImageSource(loader: MissingPhotos()))
        XCTAssertNotNil(model.shortfall)
        XCTAssertFalse(model.canExport)
    }
}

@MainActor
final class ExportControllerTests: XCTestCase {
    /// Tapping Save again while an export runs does nothing.
    func testRepeatedTapsRunOneExport() async throws {
        let (store, _) = CreationTestLibrary.makeStore()
        let controller = ExportController()
        let gate = AsyncGate()
        let renders = RenderCounter()

        let first = Task {
            await controller.save(store: store, analytics: InMemoryAnalyticsTracker(), properties: [:]) {
                renders.value += 1
                await gate.wait()
                throw CreationExportError.renderFailed
            }
        }
        try await waitUntil { controller.isBusy }
        await controller.save(store: store, analytics: InMemoryAnalyticsTracker(), properties: [:]) {
            renders.value += 1
            return []
        }
        XCTAssertEqual(renders.value, 1)
        XCTAssertTrue(controller.isBusy)

        await gate.open()
        await first.value
        XCTAssertEqual(renders.value, 1)
        XCTAssertEqual(controller.phase, .failed(CreationExportError.renderFailed.errorDescription!))
        XCTAssertFalse(controller.isBusy)
    }
}

@MainActor
final class RenderCounter {
    var value = 0
}

/// Suspends callers until opened.
actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

@MainActor
final class CreationStoreTests: XCTestCase {
    /// With limited access, images Relive saved become visible to it; they must never be
    /// imported as memories.
    func testImagesReliveSavedAreNeverImported() async {
        let saved = MemoryAsset(localIdentifier: "relive-collage", creationDate: Date(), pixelWidth: 2160, pixelHeight: 2700)
        let memory = MemoryAsset(localIdentifier: "memory", creationDate: Date(), pixelWidth: 3024, pixelHeight: 4032)
        let repository = InMemoryStoryRepository()
        let store = StoryStore(
            repository: repository,
            photoLibrary: FakePhotoLibrary(assets: [saved, memory]),
            analyzer: InstantAnalyzer(),
            placeResolver: NoPlaceLookups(),
            analytics: InMemoryAnalyticsTracker()
        )
        store.recordCreatedAssets(["relive-collage"])
        XCTAssertEqual(repository.createdAssetIDs, ["relive-collage"], "remembered across launches")

        let change = await store.syncWithAccessibleAssets()
        XCTAssertEqual(change.added, 1)
        XCTAssertEqual(Set(store.assets.keys), ["memory"])

        await store.importSelection(identifiers: ["relive-collage"])
        XCTAssertNil(store.assets["relive-collage"])
    }

    func testCreatedImagesSurviveStartOver() {
        let repository = InMemoryStoryRepository()
        repository.recordCreatedAssets(["relive-collage"])
        let store = StoryStore(
            repository: repository,
            photoLibrary: FakePhotoLibrary(assets: []),
            analyzer: InstantAnalyzer(),
            placeResolver: NoPlaceLookups(),
            analytics: InMemoryAnalyticsTracker()
        )
        XCTAssertEqual(store.createdAssetIDs, ["relive-collage"])
    }
}

@MainActor
final class SurpriseMemoryAppTests: XCTestCase {
    private func makeApp() -> (AppModel, InMemoryStoryRepository) {
        let (store, repository) = CreationTestLibrary.makeStore()
        repository.profile.relationship = RelationshipProfile(partnerName: "Emma")
        repository.profile.storyRevealedAt = Date()
        return (AppModel(storyStore: store, repository: repository, analytics: InMemoryAnalyticsTracker()), repository)
    }

    func testShowsAnAnniversaryAndKeepsItForTheDay() throws {
        let (app, repository) = makeApp()
        let now = CreationTestLibrary.now
        app.refreshSurprise(now: now)
        let surprise = try XCTUnwrap(app.surpriseMemory)
        XCTAssertEqual(surprise.anchor, .years(1))
        XCTAssertTrue(surprise.assetID.hasPrefix("trip"))
        XCTAssertNotNil(repository.profile.surprise)

        // Later the same day: the same memory.
        app.refreshSurprise(now: now.addingTimeInterval(3600 * 5))
        XCTAssertEqual(app.surpriseMemory, surprise)
    }

    func testNotNowHidesItForTheDayAndTodayRests() throws {
        let (app, _) = makeApp()
        let now = CreationTestLibrary.now
        app.refreshSurprise(now: now)
        XCTAssertNotNil(app.surpriseMemory)
        app.dismissSurprise()
        XCTAssertNil(app.surpriseMemory)
        app.refreshSurprise(now: now.addingTimeInterval(3600))
        XCTAssertNil(app.surpriseMemory, "dismissed for the rest of the day")
        app.refreshSurprise(now: now.addingTimeInterval(86_400))
        XCTAssertNil(app.surpriseMemory, "Today rests between surprises")
    }

    func testNothingOnAnOrdinaryDay() {
        let (app, _) = makeApp()
        app.refreshSurprise(now: CreationTestLibrary.calendar.date(byAdding: .month, value: -2, to: CreationTestLibrary.now)!)
        XCTAssertNil(app.surpriseMemory)
    }

    func testStartingACreationPresentsIt() {
        let (app, _) = makeApp()
        app.startCreation(.collage, from: .choosePhotos, origin: "test")
        XCTAssertEqual(app.activeCreation?.kind, .collage)
        XCTAssertEqual(app.activeCreation?.start, .choosePhotos)
    }
}
