import AVFoundation
import ReliveCore
import XCTest
@testable import Relive

// Memory Movie in the app: the editor's rules, drafts, the Premium gate, and real renders with
// AVFoundation (small, from solid stand-in photos — no PhotoKit, no live purchases).

/// Saves movies "to Photos" without PhotoKit, counting calls.
final class FakeMovieSaver: MovieSaving, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private(set) var lastFileExisted = false

    var saves: Int { lock.withLock { count } }

    func saveVideo(at url: URL) async throws -> AssetID? {
        let exists = FileManager.default.fileExists(atPath: url.path)
        return lock.withLock {
            count += 1
            lastFileExisted = exists
            return "saved-movie-\(count)"
        }
    }
}

@MainActor
enum MovieTestKit {
    /// The creation test story: a nine-photo trip moment and a five-photo evening in the same
    /// month, and two photos months later.
    static let photos = (0..<9).map { "trip-\($0)" } + (0..<5).map { "evening-\($0)" }

    static func aspects(_ store: StoryStore) -> [AssetID: Double] {
        Dictionary(uniqueKeysWithValues: store.assets.values.compactMap { asset in asset.aspectRatio.map { (asset.id, $0) } })
    }

    static func plan(_ store: StoryStore, settings: MovieSettings = MovieSettings(length: .short)) -> MoviePlan {
        MovieStoryPlanner(library: store.creationLibrary).plan(source: .photos(photos), settings: settings)
    }

    nonisolated static func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "relive-movie-test-\(name)-\(UUID().uuidString).mp4")
    }
}

@MainActor
final class MovieEditorModelTests: XCTestCase {
    func testRelivesCutThenTheUsersEditsWin() {
        let (store, _) = CreationTestLibrary.makeStore()
        let model = MovieEditorModel(source: .photos(MovieTestKit.photos), library: store.creationLibrary)
        XCTAssertTrue(model.plan.isReady)
        XCTAssertEqual(model.plan.photoIDs, MovieTestKit.photos, "hand-picked photos are kept, in order")

        // Settings never change the photos.
        let before = model.plan.photoIDs
        model.setStyle(.film)
        model.setAspect(.landscape)
        model.setShowsText(false)
        XCTAssertEqual(model.plan.photoIDs, before)
        XCTAssertEqual(model.plan.settings.style, .film)
        XCTAssertTrue(model.plan.scenes.allSatisfy { $0.text == nil })

        // Edits: remove, move, choose the opening.
        model.remove("evening-4")
        XCTAssertFalse(model.plan.photoIDs.contains("evening-4"))
        model.move("trip-0", by: 2)
        XCTAssertEqual(Array(model.plan.photoIDs.prefix(3)), ["trip-1", "trip-2", "trip-0"])
        model.makeOpening("evening-2")
        XCTAssertEqual(model.plan.cover, "evening-2")
        XCTAssertTrue(model.state.isUserCut)

        // A new length keeps the user's cut.
        let cut = model.plan.photoIDs
        model.setLength(.long)
        XCTAssertEqual(model.plan.photoIDs, cut)
    }

    func testOnlyMakeItForMeReplacesTheCut() {
        let (store, _) = CreationTestLibrary.makeStore()
        let month = MonthKey(date: store.assets["trip-0"]!.creationDate!, calendar: CreationTestLibrary.calendar)
        let model = MovieEditorModel(source: .month(month), library: store.creationLibrary)
        XCTAssertFalse(model.state.isUserCut)
        let first = model.plan
        model.remove(first.photoIDs[1])
        XCTAssertTrue(model.state.isUserCut)
        let edited = model.plan.photoIDs
        model.setStyle(.warm)
        XCTAssertEqual(model.plan.photoIDs, edited, "a style change never re-chooses photos")

        model.makeItForMe()
        XCTAssertFalse(model.state.isUserCut)
        // Changed in Real Device Polish V1: "Make it for me" re-chooses the photos and keeps the
        // style the user picked (it used to cycle the style and mostly reorder the same photos).
        XCTAssertEqual(model.plan.settings.style, .warm, "the user's style is kept")
        XCTAssertEqual(Set(model.plan.photoIDs).count, model.plan.photoIDs.count)
        XCTAssertTrue(model.plan.photoIDs.allSatisfy { MonthKey(date: store.assets[$0]!.creationDate!, calendar: CreationTestLibrary.calendar) == month }, "the same period")
    }

    func testAMovieDraftSurvivesARelaunch() throws {
        let (store, repository) = CollectionTestStore.make()
        let model = MovieEditorModel(source: .photos(MovieTestKit.photos), library: store.creationLibrary, store: store)
        model.remove("trip-3")
        model.setStyle(.editorial)
        model.makeOpening("evening-0")
        model.flush()
        let draft = try XCTUnwrap(store.drafts.first { $0.kind == .movie })
        XCTAssertEqual(draft.movie?.cover, "evening-0")

        let reopened = CollectionTestStore.reopen(repository)
        let saved = try XCTUnwrap(reopened.creation(id: draft.id))
        let state = try XCTUnwrap(saved.movie)
        let restored = MovieEditorModel(restoring: saved, state: state, library: reopened.creationLibrary(for: saved), store: reopened)
        XCTAssertEqual(restored.plan.photoIDs, model.plan.photoIDs)
        XCTAssertEqual(restored.settings.style, .editorial)
        XCTAssertTrue(restored.state.isUserCut)
        XCTAssertFalse(restored.plan.photoIDs.contains("trip-3"))
        // Nothing heavy is kept: state only.
        XCTAssertNil(saved.collage)
        XCTAssertNil(saved.story)
    }

    func testTooFewPhotosIsSaidNotPadded() {
        let (store, _) = CreationTestLibrary.makeStore()
        let model = MovieEditorModel(source: .photos(["trip-0", "trip-1", "trip-2"]), library: store.creationLibrary)
        XCTAssertFalse(model.canExport)
        XCTAssertEqual(model.plan.status, .insufficient(available: 3, required: MovieEligibility.minimumPhotos))
    }
}

@MainActor
final class MoviePremiumTests: XCTestCase {
    func testPreviewIsFreeButKeepingAMovieIsPremium() async {
        let premium = PremiumTestKit.store()
        await premium.refreshEntitlements()
        XCTAssertTrue(premium.allowance.isAvailable)
        let gate = PremiumGate()
        var exported = false
        await gate.export(.memoryMovie, entry: .memoryMovie, premium: premium) { _ in exported = true }
        XCTAssertFalse(exported, "a movie isn't the free creation")
        XCTAssertEqual(gate.request?.entry, .memoryMovie)
        XCTAssertTrue(premium.allowance.isAvailable, "the free creation is untouched")
        XCTAssertEqual(PaywallCopy(entry: .memoryMovie).context, "Keep this movie")

        let client = FakeStoreKitClient()
        client.snapshot.transactions = [client.activeTransaction(.annual)]
        let subscriber = PremiumTestKit.store(client)
        await subscriber.refreshEntitlements()
        let subscriberGate = PremiumGate()
        var kept = false
        await subscriberGate.export(.memoryMovie, entry: .memoryMovie, premium: subscriber) { succeeded in
            kept = true
            succeeded()
        }
        XCTAssertTrue(kept)
        XCTAssertNil(subscriberGate.request)
    }
}

final class MovieRendererTests: XCTestCase {
    func testASmallRenderIsAPlayableMovieOfTheRightShapeAndLength() async throws {
        let (plan, aspects) = await MainActor.run { () -> (MoviePlan, [AssetID: Double]) in
            let (store, _) = CreationTestLibrary.makeStore()
            return (MovieTestKit.plan(store), MovieTestKit.aspects(store))
        }
        XCTAssertTrue(plan.isReady)
        let url = MovieTestKit.temporaryURL("small")
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = MovieRenderer(plan: plan, loader: SolidPhotos(aspects: aspects), scale: 0.25)
        let progress = ProgressLog()
        let result = try await renderer.render(to: url) { progress.add($0) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(result.pixelSize, CGSize(width: 270, height: 480))
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, plan.duration, accuracy: 0.15)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1)
        let size = try await tracks[0].load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 270, height: 480))
        let playable = try await asset.load(.isPlayable)
        XCTAssertTrue(playable)
        XCTAssertEqual(progress.values.last, 1)
        XCTAssertTrue(progress.values == progress.values.sorted(), "progress only moves forward")

        // A frame from the middle decodes (not a corrupt file).
        let generator = AVAssetImageGenerator(asset: asset)
        let image = try await generator.image(at: CMTime(seconds: duration / 2, preferredTimescale: 600)).image
        XCTAssertEqual(image.width, 270)
    }

    func testAWideMovieAndTheExportedNumbers() async throws {
        let (plan, aspects) = await MainActor.run { () -> (MoviePlan, [AssetID: Double]) in
            let (store, _) = CreationTestLibrary.makeStore()
            return (MovieTestKit.plan(store, settings: MovieSettings(aspect: .landscape, length: .short, style: .film)), MovieTestKit.aspects(store))
        }
        let url = MovieTestKit.temporaryURL("full")
        defer { try? FileManager.default.removeItem(at: url) }
        // Full export resolution, to measure the real settings (simulator numbers only).
        let result = try await MovieRenderer(plan: plan, loader: SolidPhotos(aspects: aspects)).render(to: url) { _ in }
        XCTAssertEqual(result.pixelSize, CGSize(width: 1920, height: 1080))
        let tracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .video)
        let rate = try await tracks[0].load(.nominalFrameRate)
        XCTAssertEqual(Double(rate), 30, accuracy: 0.5)
        print("MOVIE_EXPORT_PERF duration=\(String(format: "%.1f", result.duration))s scenes=\(plan.scenes.count) render=\(String(format: "%.1f", result.seconds))s resolution=\(Int(result.pixelSize.width))x\(Int(result.pixelSize.height)) sizeMB=\(String(format: "%.1f", Double(result.bytes) / 1_048_576))")
    }

    func testCancellingStopsAndLeavesNoFile() async throws {
        let (plan, aspects) = await MainActor.run { () -> (MoviePlan, [AssetID: Double]) in
            let (store, _) = CreationTestLibrary.makeStore()
            return (MovieTestKit.plan(store, settings: MovieSettings(length: .standard)), MovieTestKit.aspects(store))
        }
        let url = MovieTestKit.temporaryURL("cancel")
        let renderer = MovieRenderer(plan: plan, loader: SolidPhotos(aspects: aspects), scale: 0.25)
        let task = Task { try await renderer.render(to: url) { _ in } }
        try await Task.sleep(for: .milliseconds(150))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("a cancelled render must not finish")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "no partial file is left")
    }

    func testAMissingPhotoFailsClearlyWithoutAFile() async throws {
        let (plan, aspects) = await MainActor.run { () -> (MoviePlan, [AssetID: Double]) in
            let (store, _) = CreationTestLibrary.makeStore()
            return (MovieTestKit.plan(store), MovieTestKit.aspects(store))
        }
        let url = MovieTestKit.temporaryURL("missing")
        let gone = plan.photoIDs[2]
        do {
            _ = try await MovieRenderer(plan: plan, loader: SolidPhotosExcept(gone, aspects: aspects), scale: 0.25).render(to: url) { _ in }
            XCTFail("a missing photo must fail")
        } catch let error as MovieExportError {
            XCTAssertEqual(error, .missingPhotos(1))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}

@MainActor
final class MovieExportControllerTests: XCTestCase {
    func testSavingIsOneExportRecordedAsRelivesOwnAndCleansUp() async throws {
        let (store, _) = CollectionTestStore.make()
        let analytics = InMemoryAnalyticsTracker()
        let plan = MovieTestKit.plan(store)
        let saver = FakeMovieSaver()
        let controller = MovieExportController(saver: saver)
        let loader = SolidPhotos(aspects: MovieTestKit.aspects(store))
        let saved = Counter()
        // Two taps: the second is ignored while the first runs.
        let first = Task { await controller.save(plan: plan, loader: loader, store: store, analytics: analytics, properties: ["source": "photos"]) { saved.value += 1 } }
        let second = Task { await controller.save(plan: plan, loader: loader, store: store, analytics: analytics, properties: ["source": "photos"]) { saved.value += 1 } }
        await first.value
        await second.value
        XCTAssertEqual(saver.saves, 1)
        XCTAssertTrue(saver.lastFileExisted)
        XCTAssertEqual(saved.value, 1)
        XCTAssertEqual(controller.phase, .finished("Saved to Photos"))
        XCTAssertTrue(store.createdAssetIDs.contains("saved-movie-1"), "never imported as a memory")
        XCTAssertFalse(FileManager.default.fileExists(atPath: MovieRenderer.temporaryFolder.path), "temporary files are removed")
        let names = analytics.events.map(\.name)
        XCTAssertTrue(names.contains(.movieExportStarted) && names.contains(.movieExportCompleted))
        // Events carry kinds only.
        for event in analytics.events where event.name == .movieExportCompleted {
            XCTAssertNil(event.properties["title"])
            XCTAssertFalse(event.properties.values.contains { $0.contains("trip-") })
        }
    }

    func testAnUnreadyMovieIsNeverRendered() async {
        let (store, _) = CollectionTestStore.make()
        let plan = MovieStoryPlanner(library: store.creationLibrary).plan(source: .photos(["trip-0", "trip-1"]), settings: MovieSettings())
        let saver = FakeMovieSaver()
        let controller = MovieExportController(saver: saver)
        await controller.save(plan: plan, loader: MissingPhotos(), store: store, analytics: InMemoryAnalyticsTracker(), properties: [:])
        XCTAssertEqual(saver.saves, 0)
        guard case .failed = controller.phase else { return XCTFail("\(controller.phase)") }
    }
}

@MainActor
final class Counter {
    var value = 0
}

/// Progress values from the renderer (called off the main thread).
final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []
    func add(_ value: Double) { lock.withLock { storage.append(value) } }
    var values: [Double] { lock.withLock { storage } }
}
