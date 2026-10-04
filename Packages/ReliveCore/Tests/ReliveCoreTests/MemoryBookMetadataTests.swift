import Foundation
import Testing
@testable import ReliveCore

/// v0.3.1: a book is described by the photos in it — titles, groups and page dates.
@Suite("Memory Book metadata")
struct MemoryBookMetadataTests {
    let now = date(2026, 10, 4)

    private func layout(_ book: MemoryBook, _ library: CreationLibrary) -> BookLayout {
        BookLayoutEngine(library: book.creationLibrary(base: library)).layout(book)
    }

    /// The fixture plus a second "September Evening" moment and photos from outside the story.
    private func library() -> (CreationLibrary, [MemoryAsset]) {
        var fixture = CreationFixture.make()
        func evening(_ key: String, _ day: Int) {
            let members = (0..<3).map { makeAsset("\(key)-\($0)", at: date(2025, 9, day, 19, $0 * 10)) }
            for asset in members { fixture.assets[asset.id] = asset }
            fixture.story.moments.append(Moment(
                id: CreationFixture.momentID(key), kind: .event, assetIDs: members.map(\.id), featuredAssetIDs: members.map(\.id),
                startDate: members.first?.creationDate, endDate: members.last?.creationDate,
                title: MomentTitle(primary: "September Evening", secondary: "September 2025")
            ))
        }
        evening("eve5", 5)
        evening("eve10", 10)
        fixture.story.moments.sort { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
        let picks = [
            makeAsset("lib-oct-a", at: date(2025, 10, 2, 18)),
            makeAsset("lib-oct-b", at: date(2025, 10, 2, 18, 30), width: 4032, height: 3024),
            makeAsset("lib-undated", at: nil),
        ]
        return (fixture.library.addingPhotoLibraryAssets(picks), picks)
    }

    @Test("Photos from several months don't make a 'September Together' book")
    func multiMonthTitle() throws {
        let (library, _) = library()
        let chosen = ["kas-0", "kas-1", "kekova-0", "moda-0", "eve5-0", "eve10-1"]
        let book = try MemoryBookBuilder(library: library).makeBook(from: .photos(chosen), now: now).get()
        let layout = layout(book, library)
        #expect(layout.facts.title == .year(2025))
        #expect(layout.facts.title != .month(MonthKey(year: 2025, month: 9)))
        #expect(layout.pages[0].dateSpan == DateSpan(start: date(2025, 8, 6, 10), end: date(2025, 9, 12, 19)))
    }

    @Test("A September book given an August photo stops calling itself September")
    func editedMonthBook() throws {
        let (library, _) = library()
        var book = try MemoryBookBuilder(library: library).makeBook(from: .month(MonthKey(year: 2025, month: 9)), now: now).get()
        #expect(layout(book, library).facts.title == .month(MonthKey(year: 2025, month: 9)))
        let ok = book.setPhotos(book.photoIDs + ["kas-2"])
        #expect(ok)
        #expect(layout(book, library).facts.title == .year(2025))
    }

    @Test("A photo from outside the story never takes its neighbour's name or date")
    func noInheritedSection() throws {
        let (library, picks) = library()
        var book = MemoryBook(createdAt: now, source: .photos([]), photoIDs: ["moda-0", "moda-1", "moda-2", "lib-oct-a", "lib-oct-b", "moda-3"])
        book.rememberPhotoLibraryAssets(picks)
        let sections = BookLayoutEngine(library: book.creationLibrary(base: library)).sections(for: book, photos: book.photoIDs)
        let october = try #require(sections.first { $0.photos.contains("lib-oct-a") })
        #expect(october.photos == ["lib-oct-a", "lib-oct-b"])
        #expect(october.title == nil, "no moment, so no moment name")
        #expect(october.place == nil)
        #expect(october.dateSpan == DateSpan(start: date(2025, 10, 2, 18), end: date(2025, 10, 2, 18, 30)))
        #expect(sections.map(\.photos) == [["moda-0", "moda-1", "moda-2"], ["lib-oct-a", "lib-oct-b"], ["moda-3"]])
        #expect(book.photoLibraryAssets.map(\.id) == ["lib-oct-a", "lib-oct-b"], "only photos in the book are remembered")
    }

    @Test("Undated photos from outside the story get no invented date or opening page")
    func undatedOutside() {
        let (library, picks) = library()
        var book = MemoryBook(createdAt: now, source: .photos([]), photoIDs: ["moda-0", "moda-1", "lib-undated", "moda-2", "moda-3", "afternoon-0"])
        book.rememberPhotoLibraryAssets(picks)
        let layout = layout(book, library)
        let pageWithUndated = layout.pages.first { $0.kind != .cover && $0.photoIDs.contains("lib-undated") }
        #expect(pageWithUndated?.kind == .photos, "no opening page for a group with nothing true to say")
        #expect(pageWithUndated?.runningDate == nil)
        #expect(layout.facts.dateSpan == nil, "the book can't claim dates for a photo without one")
    }

    @Test("A generic name used twice gives way to the date")
    func noRepeatedGenericTitles() {
        let (library, _) = library()
        let book = MemoryBook(createdAt: now, source: .photos([]), photoIDs: ["eve5-0", "eve5-1", "eve5-2", "eve10-0", "eve10-1", "eve10-2"])
        let openers = layout(book, library).pages.filter { $0.kind == .opener }
        #expect(openers.count == 2)
        #expect(openers[0].title == .named("September Evening"))
        #expect(openers[1].title == nil, "shown as its date instead")
        #expect(openers[1].dateSpan == DateSpan(start: date(2025, 9, 10, 19), end: date(2025, 9, 10, 19, 20)))
    }

    @Test("Each page's footer carries the dates of its own photos")
    func pageDates() throws {
        let (library, _) = library()
        let book = try MemoryBookBuilder(library: library).makeBook(from: .moment(CreationFixture.make().moment("kas").id), now: now).get()
        let layout = layout(book, library)
        for page in layout.pages where page.kind == .photos {
            #expect(page.runningDate == library.metadata(of: page.photoIDs).dateSpan)
        }
        let spans = Set(layout.pages.filter { $0.kind == .photos }.compactMap(\.runningDate))
        #expect(spans.count > 1, "pages aren't all stamped with the book's dates")
    }

    @Test("Favorites make a book")
    func favoritesBook() throws {
        var fixture = CreationFixture.make()
        for id in ["kas-0", "kas-4", "kekova-1", "moda-2", "afternoon-1", "coffee-3"] { fixture.assets[id]?.isFavorite = true }
        let book = try MemoryBookBuilder(library: fixture.library).makeBook(from: .favorites, now: now).get()
        #expect(book.photoIDs == ["kas-0", "kas-4", "kekova-1", "moda-2", "afternoon-1", "coffee-3"])
        #expect(layout(book, fixture.library).facts.title == nil, "2025 and 2026: no single label")
    }

    @Test("A book of photo-library photos keeps their metadata across a restart")
    func photoLibraryBookPersists() throws {
        let (library, picks) = library()
        let chosen = ["lib-oct-a", "lib-oct-b", "moda-0", "moda-1", "moda-2", "moda-3"]
        let book = try MemoryBookBuilder(library: library).makeBook(from: .photos(chosen), now: now).get()
        #expect(Set(book.photoLibraryAssets.map(\.id)) == ["lib-oct-a", "lib-oct-b"])
        let restored = try JSONDecoder().decode(MemoryBook.self, from: JSONEncoder().encode(book))
        #expect(restored == book)
        // After a restart the story library knows nothing of the picks; the book brings them.
        let fresh = CreationFixture.make().library
        let layout = layout(restored, fresh)
        #expect(Set(layout.photoIDs) == Set(chosen))
        #expect(layout.facts.title == .year(2025), "September and October")
        _ = picks
    }

    @Test("Books saved before v0.3.1 still open")
    func oldBookDecodes() throws {
        let json = #"""
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","version":1,"createdAt":0,"updatedAt":0,
         "source":{"moment":{"_0":"6F9619FF-8B86-D011-B42D-00C04FC964FF"}},"style":"film",
         "photoIDs":["a","b","c","d"],"includesMomentNotes":true}
        """#
        let book = try JSONDecoder().decode(MemoryBook.self, from: Data(json.utf8))
        #expect(book.photoIDs == ["a", "b", "c", "d"])
        #expect(book.photoLibraryAssets.isEmpty)
        #expect(book.style == .film)
    }

    // MARK: - Pages

    @Test("A portrait and a landscape make an asymmetric spread, neither cropped")
    func featureSpread() {
        let library = CreationFixture.make().library
        let engine = BookLayoutEngine(library: library)
        let metrics = BookStyleMetrics.metrics(for: .classic)
        let page = engine.photoPage(["kas-0", "coffee-0"], style: .classic, metrics: metrics) // portrait, landscape
        #expect(page.template == .feature)
        let frames = page.slots.map(\.frame)
        #expect(abs(frames[0].aspectRatio - 0.75) < 0.01 && abs(frames[1].aspectRatio - 4.0 / 3.0) < 0.01)
        #expect(!frames[0].overlaps(frames[1]))
        #expect(frames[0].width > frames[1].width, "the portrait leads")
        let reversed = engine.photoPage(["coffee-0", "kas-0"], style: .classic, metrics: metrics)
        #expect(reversed.slots.map(\.assetID) == ["coffee-0", "kas-0"], "photos stay in reading order")
    }

    @Test("Page splits follow the photos' shapes and leave no lone photo")
    func photosPerPage() {
        let p = PhotoOrientation.portrait, l = PhotoOrientation.landscape
        #expect(BookLayoutEngine.photosPerPage(shapes: [l, l, l, l], remaining: 6, previous: 0) == 2, "landscapes pair up")
        #expect(BookLayoutEngine.photosPerPage(shapes: [p, p, p, p], remaining: 6, previous: 0) == 4)
        #expect(BookLayoutEngine.photosPerPage(shapes: [p, p, p, p], remaining: 6, previous: 4) == 3, "not two grids in a row")
        #expect(BookLayoutEngine.photosPerPage(shapes: [p, p, p, p], remaining: 5, previous: 0) == 3, "4 + 1 would leave one alone")
        #expect(BookLayoutEngine.photosPerPage(shapes: [l, l, p], remaining: 3, previous: 0) == 3, "2 + 1 would leave one alone")
        #expect(BookLayoutEngine.photosPerPage(shapes: [p, p], remaining: 2, previous: 2) == 2)
    }

    @Test("Every photo of every book appears once, in order")
    func everyPhotoOnce() throws {
        let (library, _) = library()
        for source in [CreationSource.year(2025), .month(MonthKey(year: 2025, month: 9)), .trip(CreationFixture.tripID)] {
            let book = try MemoryBookBuilder(library: library).makeBook(from: source, now: now).get()
            let pages = layout(book, library).pages.filter { $0.kind != .cover }.flatMap(\.photoIDs)
            #expect(pages == book.photoIDs, "\(source)")
        }
    }
}
