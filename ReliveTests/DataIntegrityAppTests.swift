import Foundation
import ReliveCore
import SwiftData
import XCTest
@testable import Relive

// The data-integrity rules through the real app layers: the store, its import and repair, and
// SwiftData on disk. Like the other hosted tests, nothing touches PhotoKit: the photo library is
// a fake that reports fixed metadata.

/// The acceptance library (44 photos, six months of two years) in a fixed UTC+3 calendar.
@MainActor
enum IntegrityLibrary {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 3 * 3600) ?? .current
        return calendar
    }()

    static let months: [(String, Int, Int, Int, Int)] = [
        ("apr25", 2025, 4, 12, 8), ("may25", 2025, 5, 3, 5), ("sep25", 2025, 9, 10, 12),
        ("jan26", 2026, 1, 5, 6), ("sep26", 2026, 9, 18, 9), ("oct26", 2026, 10, 4, 4),
    ]

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    /// What the photo library reports.
    static func assets() -> [MemoryAsset] {
        months.flatMap { prefix, year, month, day, count in
            (0..<count).map { index in
                MemoryAsset(
                    localIdentifier: "\(prefix)-\(index)",
                    creationDate: date(year, month, day, 14, index * 7),
                    location: index.isMultiple(of: 3) ? GeoCoordinate(latitude: 36.2, longitude: 29.64) : nil,
                    pixelWidth: 3024,
                    pixelHeight: 4032
                )
            }
        } + [MemoryAsset(localIdentifier: "undated-0", creationDate: nil, pixelWidth: 3024, pixelHeight: 4032)]
    }

    static func store(repository: any StoryRepository, library: [MemoryAsset]) -> StoryStore {
        StoryStore(
            repository: repository,
            photoLibrary: FakePhotoLibrary(assets: library),
            analyzer: InstantAnalyzer(),
            placeResolver: NoPlaceLookups(),
            analytics: InMemoryAnalyticsTracker(),
            calendar: calendar
        )
    }
}

/// An on-disk SwiftData store that can be opened again, as the app does after a relaunch.
@MainActor
final class DiskStore {
    let folder: URL
    let url: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "relive-integrity-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appending(path: "Relive.store")
    }

    /// A fresh container and repository over the same file (a new launch).
    func open() throws -> SwiftDataStoryRepository {
        let schema = Schema(PersistenceSchema.models)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        containers.append(container)
        return SwiftDataStoryRepository(container: container)
    }

    private var containers: [ModelContainer] = []

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }
}

@MainActor
final class CaptureDateIntegrityTests: XCTestCase {
    // A, B, C, L, M
    func testImportAndRelaunchKeepExactDatesAndUnknowns() async throws {
        let disk = try DiskStore()
        let library = IntegrityLibrary.assets()
        let store = IntegrityLibrary.store(repository: try disk.open(), library: library)
        await store.importSelection(identifiers: library.map(\.id))
        await store.process()

        // A relaunch: a new container over the same file.
        let reopened = IntegrityLibrary.store(repository: try disk.open(), library: library)
        XCTAssertEqual(reopened.assets.count, 45, "nothing lost or duplicated")
        for source in library {
            let stored = try XCTUnwrap(reopened.assets[source.id])
            XCTAssertEqual(stored.creationDate, source.creationDate, "\(source.id): the exact capture date survives storage")
            XCTAssertEqual(stored.location, source.location, "\(source.id): the location (or none) survives storage")
        }
        XCTAssertNil(reopened.assets["undated-0"]?.creationDate, "unknown stays unknown")
        XCTAssertFalse(reopened.story.moments.isEmpty, "the story survives storage")
    }

    // D, E, G, H, I through the store
    func testRecapsAndYearsAfterImportAreExact() async throws {
        let library = IntegrityLibrary.assets()
        let store = IntegrityLibrary.store(repository: InMemoryStoryRepository(), library: library)
        await store.importSelection(identifiers: library.map(\.id))
        await store.process()
        let creation = store.creationLibrary
        let index = TemporalIndex(library: creation)
        XCTAssertEqual(index.entries.count, 44)
        XCTAssertEqual(index.undatedCount, 1)
        XCTAssertEqual(index.months.count, 6)
        XCTAssertEqual(index.countsByMonth[MonthKey(year: 2026, month: 9)], 9, "September 2026 holds only its own 9 photos")
        let years = YearInReviewBuilder(library: creation)
        XCTAssertEqual(years.availableYears(), [2026, 2025])
        XCTAssertEqual(years.review(for: 2025).statistics.memoryCount, 25)
        XCTAssertEqual(years.review(for: 2026).statistics.memoryCount, 19)
        XCTAssertEqual(years.review(for: 2025).firstMemory?.date, IntegrityLibrary.date(2025, 4, 12, 14, 0))
        XCTAssertEqual(years.review(for: 2026).firstMemory?.date, IntegrityLibrary.date(2026, 1, 5, 14, 0))
        let april = MonthlyRecapBuilder(library: creation).recap(for: MonthKey(year: 2025, month: 4))
        XCTAssertEqual(Set(april.moments.flatMap(\.assetIDs)), Set((0..<8).map { "apr25-\($0)" }))
    }

    // N, O: an install whose stored dates were wrong is repaired from the library, keeps its
    // notes, hidden moments and favorites, and doesn't duplicate anything.
    func testRepairFixesStoredDatesAndKeepsUserState() async throws {
        let disk = try DiskStore()
        let library = IntegrityLibrary.assets()
        // What an earlier run stored: April's photos dated September 10, 2026.
        let wrong = library.map { asset -> MemoryAsset in
            guard asset.id.hasPrefix("apr25") else { return asset }
            var copy = asset
            let index = Int(asset.id.split(separator: "-")[1]) ?? 0
            copy.creationDate = IntegrityLibrary.date(2026, 9, 10, 20, index * 7)
            return copy
        }
        let first = IntegrityLibrary.store(repository: try disk.open(), library: wrong)
        await first.importSelection(identifiers: wrong.map(\.id))
        await first.process()
        let aprilMoment = try XCTUnwrap(first.story.moments.first { $0.assetIDs.contains("apr25-0") })
        XCTAssertEqual(first.calendar.component(.year, from: try XCTUnwrap(aprilMoment.startDate)), 2026, "the corrupted state")
        let mayMoment = try XCTUnwrap(first.story.moments.first { $0.assetIDs.contains("may25-0") })
        first.setNote("The first trip", for: aprilMoment.id)
        first.setFavorite(.moment, aprilMoment.id.uuidString, isFavorite: true)
        first.setFavorite(.memory, "apr25-3", isFavorite: true)
        first.setHidden(true, for: mayMoment.id)

        // Next launch: the library reports the real dates.
        let store = IntegrityLibrary.store(repository: try disk.open(), library: library)
        let repaired = await store.repairMetadata(now: IntegrityLibrary.date(2026, 10, 5))
        let result = try XCTUnwrap(repaired)
        XCTAssertEqual(Set(result.changes.map(\.assetID)), Set((0..<8).map { "apr25-\($0)" }))
        XCTAssertEqual(store.assets.count, 45, "no memory added, removed or duplicated")
        XCTAssertEqual(store.assets["apr25-0"]?.creationDate, IntegrityLibrary.date(2025, 4, 12, 14, 0))
        let repairedMoment = try XCTUnwrap(store.story.moments.first { $0.assetIDs.contains("apr25-0") })
        XCTAssertEqual(store.calendar.component(.year, from: try XCTUnwrap(repairedMoment.startDate)), 2025, "the story was rebuilt")
        XCTAssertEqual(repairedMoment.id, aprilMoment.id, "same moment identity")
        XCTAssertEqual(store.userState(for: repairedMoment.id).note, "The first trip", "notes stay")
        XCTAssertTrue(store.isFavorite(.moment, repairedMoment.id.uuidString), "moment favorites stay")
        XCTAssertTrue(store.isFavorite(.memory, "apr25-3"), "memory favorites stay")
        XCTAssertTrue(store.userState(for: mayMoment.id).isHidden, "hidden stays hidden")
        XCTAssertEqual(YearInReviewBuilder(library: store.creationLibrary).review(for: 2025).firstMemory?.assetID, "apr25-0")
        XCTAssertNil(MonthlyRecapBuilder(library: store.creationLibrary).recap(for: MonthKey(year: 2026, month: 9)).moments.first { $0.assetIDs.contains("apr25-0") })

        // Idempotent: running it again changes nothing and rebuilds nothing.
        let generated = store.story.generatedAt
        let secondRun = await store.repairMetadata(now: IntegrityLibrary.date(2026, 10, 5))
        let again = try XCTUnwrap(secondRun)
        XCTAssertTrue(again.changes.isEmpty)
        XCTAssertEqual(store.story.generatedAt, generated)
        XCTAssertEqual(store.assets.count, 45)

        // And it all survives the next launch.
        let relaunched = IntegrityLibrary.store(repository: try disk.open(), library: library)
        XCTAssertEqual(relaunched.assets["apr25-0"]?.creationDate, IntegrityLibrary.date(2025, 4, 12, 14, 0))
        XCTAssertTrue(relaunched.isFavorite(.memory, "apr25-3"))
    }

    // L, M: the library knowing nothing never becomes something.
    func testRepairNeverInventsMetadata() async throws {
        let stored = [MemoryAsset(localIdentifier: "a", creationDate: IntegrityLibrary.date(2025, 4, 12), location: GeoCoordinate(latitude: 36.2, longitude: 29.64), pixelWidth: 10, pixelHeight: 10)]
        let repository = InMemoryStoryRepository(assets: stored)
        // The library now has no date and no place for it (e.g. stripped in an edit).
        let store = IntegrityLibrary.store(repository: repository, library: [MemoryAsset(localIdentifier: "a", creationDate: nil, pixelWidth: 10, pixelHeight: 10)])
        let repaired = await store.repairMetadata()
        let result = try XCTUnwrap(repaired)
        XCTAssertEqual(result.changes.first?.dateChanged, true)
        XCTAssertNil(store.assets["a"]?.creationDate, "unknown, not now and not the old value")
        XCTAssertNil(store.assets["a"]?.location)
    }
}

@MainActor
final class PersistenceAcrossRelaunchTests: XCTestCase {
    // R
    func testFavoritesSurviveARelaunch() async throws {
        let disk = try DiskStore()
        let library = IntegrityLibrary.assets()
        let store = IntegrityLibrary.store(repository: try disk.open(), library: library)
        await store.importSelection(identifiers: library.map(\.id))
        await store.process()
        let moment = try XCTUnwrap(store.story.moments.first)
        store.setFavorite(.memory, "sep25-2", isFavorite: true)
        store.setFavorite(.memory, "sep25-2", isFavorite: true)
        store.setFavorite(.moment, moment.id.uuidString, isFavorite: true)

        let relaunched = IntegrityLibrary.store(repository: try disk.open(), library: library)
        XCTAssertTrue(relaunched.isFavorite(.memory, "sep25-2"))
        XCTAssertTrue(relaunched.isFavorite(.moment, moment.id.uuidString))
        XCTAssertEqual(relaunched.favorites.count, 2, "no duplicates")
        relaunched.setFavorite(.memory, "sep25-2", isFavorite: false)
        XCTAssertFalse(IntegrityLibrary.store(repository: try disk.open(), library: library).isFavorite(.memory, "sep25-2"))
    }

    // S: drafts written by the editors are on disk and reopen exactly after a relaunch.
    func testDraftsSurviveARelaunch() async throws {
        let disk = try DiskStore()
        let library = IntegrityLibrary.assets()
        let store = IntegrityLibrary.store(repository: try disk.open(), library: library)
        await store.importSelection(identifiers: library.map(\.id))
        await store.process()
        let moment = try XCTUnwrap(store.story.moments.first { $0.assetIDs.contains("sep25-0") })

        let collage = CollageEditorModel(source: .moment(moment.id), photos: Array(moment.assetIDs.prefix(5)), library: store.creationLibrary, store: store)
        collage.style = collage.style == .film ? .grid : .film
        XCTAssertEqual(store.drafts.count, 1, "the first change writes the draft at once")
        collage.aspectRatio = .square
        collage.showsPlace = false
        let collageState = collage.state
        collage.flush()

        let story = StoryMakerModel(source: .moment(moment.id), library: store.creationLibrary, store: store)
        story.setStyle(story.style == .film ? .editorial : .film)
        if let opening = story.cards.first { story.toggleDate(of: opening.id) }
        let design = try XCTUnwrap(story.design)
        story.flush()

        // Relaunch: a new container over the same file.
        let relaunched = IntegrityLibrary.store(repository: try disk.open(), library: library)
        XCTAssertEqual(relaunched.drafts.count, 2)
        let collageDraft = try XCTUnwrap(relaunched.drafts.first { $0.kind == .collage })
        XCTAssertEqual(collageDraft.collage, collageState)
        let storyDraft = try XCTUnwrap(relaunched.drafts.first { $0.kind == .story })
        XCTAssertEqual(storyDraft.story?.design, design, "cards, order, layouts, style and choices survive")
        let resumed = StoryMakerModel(restoring: storyDraft, state: try XCTUnwrap(storyDraft.story), library: relaunched.creationLibrary(for: storyDraft), store: relaunched)
        XCTAssertEqual(resumed.design, design)
        XCTAssertTrue(resumed.missingInStory.isEmpty)
    }
}

@MainActor
final class CollageReorderTests: XCTestCase {
    func testDraggingAPhotoMovesItAndTheOthersShift() throws {
        let (store, _) = CollectionTestStore.make()
        let trip = store.story.moments[0]
        let model = CollageEditorModel(source: .moment(trip.id), photos: Array(trip.assetIDs.prefix(5)), library: store.creationLibrary, store: store)
        let before = model.photoIDs
        model.movePhoto(before[0], toPositionOf: before[3])
        XCTAssertEqual(model.photoIDs, [before[1], before[2], before[3], before[0], before[4]])
        model.movePhoto(before[4], toPositionOf: before[1])
        XCTAssertEqual(model.photoIDs, [before[4], before[1], before[2], before[3], before[0]])
        XCTAssertEqual(Set(model.photoIDs), Set(before), "nothing added or lost")
        XCTAssertEqual(model.layout.slots.count, before.count, "the layout follows the new order")
        // A photo from outside the collage, or onto itself, changes nothing.
        let current = model.photoIDs
        model.movePhoto("not-in-collage", toPositionOf: current[0])
        model.movePhoto(current[2], toPositionOf: current[2])
        XCTAssertEqual(model.photoIDs, current)
        // The move is kept as a draft, in the new order.
        model.flush()
        XCTAssertEqual(store.drafts.first?.collage?.photoIDs, current)
    }
}
