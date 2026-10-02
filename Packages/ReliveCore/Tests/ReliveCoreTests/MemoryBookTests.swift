import Foundation
import Testing
@testable import ReliveCore

@Suite("Memory Book")
struct MemoryBookTests {
    let fixture = CreationFixture.make()
    let now = date(2026, 4, 10)

    func book(_ source: CreationSource, fixture: CreationFixture? = nil) throws -> MemoryBook {
        try MemoryBookBuilder(library: (fixture ?? self.fixture).library).makeBook(from: source, now: now).get()
    }

    func layout(_ book: MemoryBook, fixture: CreationFixture? = nil) -> BookLayout {
        BookLayoutEngine(library: (fixture ?? self.fixture).library).layout(book)
    }

    /// Every usable photo appears exactly once inside the book (the cover may repeat one).
    func assertEachPhotoOnce(_ layout: BookLayout, sourceLocation: SourceLocation = #_sourceLocation) {
        let inside = layout.pages.filter { $0.kind != .cover }.flatMap(\.photoIDs)
        #expect(inside.count == Set(inside).count, sourceLocation: sourceLocation)
        #expect(Set(inside) == Set(layout.photoIDs), sourceLocation: sourceLocation)
    }

    // MARK: - Sources

    @Test("A moment becomes a book of its photos, without section pages")
    func momentBook() throws {
        let kas = fixture.moment("kas")
        let book = try book(.moment(kas.id))
        #expect(book.photoIDs == kas.assetIDs, "all 8 photos, in the order they were taken")
        let layout = layout(book)
        #expect(layout.pages.first?.kind == .cover)
        #expect(layout.pages.last?.kind == .closing)
        #expect(!layout.pages.contains { $0.kind == .opener || $0.kind == .tripTitle })
        #expect(layout.facts.title == .named("Kaş"))
        #expect(layout.pages[0].slots.count == 1, "the cover has a photo")
        assertEachPhotoOnce(layout)
    }

    @Test("A trip opens each of its moments with their real names")
    func tripBook() throws {
        let book = try book(.trip(CreationFixture.tripID))
        #expect(book.photoIDs.count == 12, "8 + 4 usable photos; the screenshot is left out")
        #expect(book.photoIDs == book.photoIDs.sorted(by: fixture.library.chronologicalOrder))
        let layout = layout(book)
        let openers = layout.pages.filter { $0.kind == .opener }
        #expect(openers.map(\.title) == [.named("Kaş"), .named("Kekova")])
        #expect(openers.allSatisfy { $0.dateSpan != nil && $0.place != nil })
        #expect(!layout.pages.contains { $0.kind == .tripTitle }, "the whole book is the trip")
        #expect(layout.facts.title == .named("Kaş"))
        assertEachPhotoOnce(layout)
    }

    @Test("A month book has a section per moment")
    func monthBook() throws {
        let layout = layout(try book(.month(MonthKey(year: 2025, month: 9))))
        #expect(layout.photoIDs.count == 6)
        #expect(layout.pages.filter { $0.kind == .opener }.map(\.title) == [.named("Moda Evening"), .named("September Afternoon")])
        #expect(layout.facts.title == .month(MonthKey(year: 2025, month: 9)))
        #expect(layout.pages.filter { $0.kind == .opener }.last?.place == nil, "no invented place")
        assertEachPhotoOnce(layout)
    }

    @Test("A year book announces a trip once, before its moments")
    func yearBook() throws {
        let layout = layout(try book(.year(2025)))
        #expect(layout.photoIDs.count == 18)
        let kinds = layout.pages.map(\.kind)
        let trips = layout.pages.filter { $0.kind == .tripTitle }
        #expect(trips.count == 1)
        #expect(trips.first?.title == .named("Kaş"))
        let tripIndex = try #require(kinds.firstIndex(of: .tripTitle))
        #expect(kinds[tripIndex + 1] == .opener)
        #expect(layout.pages.filter { $0.kind == .opener }.count == 4)
        assertEachPhotoOnce(layout)
    }

    @Test("Chosen photos keep the order they were chosen in")
    func chosenPhotos() throws {
        let chosen = ["coffee-2", "kas-1", "moda-0", "kas-0", "coffee-0"]
        let book = try book(.photos(chosen))
        #expect(book.photoIDs == chosen)
        let layout = layout(book)
        let order = layout.pages.filter { $0.kind != .cover }.flatMap(\.photoIDs)
        #expect(order == chosen)
    }

    @Test("Too few photos, or a hidden moment, makes no book")
    func insufficient() {
        let builder = MemoryBookBuilder(library: fixture.library)
        #expect(builder.makeBook(from: .moment(fixture.moment("afternoon").id), now: now) == .failure(.notEnoughPhotos(available: 2, required: 4)))
        #expect(builder.makeBook(from: .moment(fixture.moment("spring").id), now: now) == .failure(.notEnoughPhotos(available: 0, required: 4)))
        #expect(builder.makeBook(from: .photos(["kas-0", "kas-1", "moda-video"]), now: now) == .failure(.notEnoughPhotos(available: 2, required: 4)))
    }

    // MARK: - Layout

    @Test("Portraits alone fill the page; landscapes alone keep their shape; pairs aren't cropped")
    func orientation() throws {
        let landscapes = layout(try book(.month(MonthKey(year: 2026, month: 4)))) // six landscape photos
        let page = CanvasSize(width: BookLayoutEngine.pageSize.width, height: BookLayoutEngine.pageSize.height)
        let pageRect = LayoutRect(x: 0, y: 0, width: page.width, height: page.height)
        for page in landscapes.pages {
            for slot in page.slots {
                #expect(pageRect.contains(slot.frame))
                #expect(slot.frame.width > 50 && slot.frame.height > 50)
            }
            switch page.template {
            case .single?:
                #expect(abs(page.slots[0].frame.aspectRatio - 4.0 / 3.0) < 0.01, "landscape kept whole")
            case .pair?:
                #expect(page.slots.allSatisfy { abs($0.frame.aspectRatio - 4.0 / 3.0) < 0.01 })
            case .fullBleed?:
                Issue.record("a landscape photo shouldn't be cropped to fill a portrait page")
            default:
                break
            }
        }

        let portraits = layout(try book(.moment(fixture.moment("kas").id)))
        for page in portraits.pages where page.template == .single || page.template == .fullBleed {
            #expect(page.template == .fullBleed, "a portrait photo alone fills the page")
        }
    }

    @Test("Pages vary instead of repeating one arrangement")
    func variety() throws {
        let layout = layout(try book(.trip(CreationFixture.tripID)))
        let templates = layout.pages.compactMap { $0.kind == .photos ? $0.template : nil }
        #expect(Set(templates).count >= 3)
        for index in templates.indices.dropFirst(2) {
            #expect(!(templates[index] == templates[index - 1] && templates[index] == templates[index - 2]))
        }
    }

    @Test("Layouts are deterministic")
    func deterministic() throws {
        let book = try book(.year(2025))
        #expect(layout(book) == layout(book))
    }

    @Test("Changing the style changes the look, never the content")
    func styles() throws {
        var book = try book(.year(2025))
        book.note = "For us."
        let classic = layout(book)
        for style in BookStyle.allCases {
            book.style = style
            let other = layout(book)
            #expect(other.pages.map(\.kind) == classic.pages.map(\.kind))
            #expect(other.pages.map(\.photoIDs) == classic.pages.map(\.photoIDs))
            #expect(other.pages.map(\.title) == classic.pages.map(\.title))
            #expect(other.pages.map(\.text) == classic.pages.map(\.text))
        }
        book.style = .editorial
        #expect(layout(book).pages.map { $0.slots.map(\.frame) } != classic.pages.map { $0.slots.map(\.frame) })
    }

    @Test("Photos removed from the library drop out; the cover falls back")
    func missingPhotos() throws {
        var book = try book(.moment(fixture.moment("kas").id))
        book.coverAssetID = "kas-3"
        var fixture = fixture
        fixture.unavailable = ["kas-3", "kas-5"]
        let layout = layout(book, fixture: fixture)
        #expect(layout.missingAssetIDs == ["kas-3", "kas-5"])
        #expect(!layout.pages.flatMap(\.photoIDs).contains("kas-3"))
        #expect(layout.pages[0].photoIDs.first != "kas-3")
        assertEachPhotoOnce(layout)
    }

    @Test("The cover the user chose is used")
    func coverChoice() throws {
        var book = try book(.moment(fixture.moment("kas").id))
        book.coverAssetID = "kas-6"
        #expect(layout(book).pages[0].photoIDs == ["kas-6"])
        book.coverAssetID = "not-in-book"
        #expect(layout(book).pages[0].photoIDs != ["not-in-book"])
    }

    @Test("The user's own words: a book note after the cover, moment notes after their moment")
    func notes() throws {
        var fixture = fixture
        let kekova = fixture.moment("kekova").id
        fixture.userStates[kekova] = MomentUserState(note: "The boat to the island.")
        var book = try book(.trip(CreationFixture.tripID), fixture: fixture)
        book.note = "  For Emma.  "
        let pages = layout(book, fixture: fixture).pages
        #expect(pages[1].kind == .bookNote)
        #expect(pages[1].text == "For Emma.")
        let noteIndex = try #require(pages.firstIndex { $0.kind == .momentNote })
        #expect(pages[noteIndex].text == "The boat to the island.")
        #expect(pages[noteIndex - 1].kind == .opener && pages[noteIndex - 1].title == .named("Kekova"))

        book.includesMomentNotes = false
        book.note = "   "
        let quiet = layout(book, fixture: fixture).pages
        #expect(!quiet.contains { $0.kind == .momentNote || $0.kind == .bookNote })
    }

    @Test("Pages are numbered after the cover and pair into spreads")
    func folios() throws {
        let layout = layout(try book(.year(2025)))
        #expect(layout.pages[0].folio == nil)
        #expect(layout.pages.dropFirst().map(\.folio) == Array(1..<layout.pages.count).map { Optional($0) })
        #expect(layout.spreads.first == [0])
        #expect(layout.spreads.dropFirst().dropLast().allSatisfy { $0.count == 2 })
        #expect(layout.spreads.flatMap { $0 } == layout.pages.map(\.id))
    }

    @Test("A large book stays bounded and lays out quickly")
    func largeBook() throws {
        var assets: [MemoryAsset] = []
        var moments: [Moment] = []
        for momentIndex in 0..<40 {
            let start = date(2024, 1 + momentIndex % 12, 1 + momentIndex % 27, 10)
            let members = (0..<9).map { index in
                makeAsset("big-\(momentIndex)-\(index)", at: start.addingTimeInterval(Double(index) * 300),
                          width: index.isMultiple(of: 3) ? 4032 : 3024, height: index.isMultiple(of: 3) ? 3024 : 4032)
            }
            assets += members
            moments.append(Moment(
                id: UUID(), kind: .event, assetIDs: members.map(\.id), featuredAssetIDs: members.map(\.id),
                startDate: start, endDate: start, title: MomentTitle(primary: "Moment \(momentIndex)")
            ))
        }
        moments.sort { $0.sortDate < $1.sortDate }
        let library = CreationLibrary(
            story: Story(generatedAt: now, moments: moments, chapters: []),
            assets: Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) }),
            userStates: [:], unavailableAssetIDs: [], calendar: testCalendar
        )
        let book = try MemoryBookBuilder(library: library).makeBook(from: .year(2024), now: now).get()
        #expect(book.photoIDs.count == BookLimits.maximumPhotos, "360 photos are sampled down to 60")
        let started = Date()
        let layout = BookLayoutEngine(library: library).layout(book)
        #expect(Date().timeIntervalSince(started) < 1)
        #expect(layout.pages.count < 120)
        assertEachPhotoOnce(layout)
    }

    // MARK: - Persistence

    @Test("A book survives encoding, for every kind of source")
    func codable() throws {
        let sources: [CreationSource] = [
            .moment(fixture.moment("kas").id), .trip(CreationFixture.tripID), .photos(["kas-0", "moda-1"]),
            .month(MonthKey(year: 2025, month: 9)), .year(2025),
        ]
        for source in sources {
            var original = MemoryBook(createdAt: now, source: source, style: .film, photoIDs: ["kas-0", "kas-1"], coverAssetID: "kas-1", note: "Ours")
            original.includesMomentNotes = false
            let data = try JSONEncoder().encode(original)
            #expect(try JSONDecoder().decode(MemoryBook.self, from: data) == original)
        }
    }

    @Test("Refreshing follows the source and keeps the user's choices")
    func refresh() throws {
        var book = try book(.moment(fixture.moment("kas").id))
        book.style = .film
        book.note = "Ours"
        book.coverAssetID = "kas-7"
        book.photoIDs = Array(book.photoIDs.prefix(5))
        var fixture = fixture
        fixture.unavailable = ["kas-7"]
        let refreshed = MemoryBookBuilder(library: fixture.library).refreshed(book, now: now)
        #expect(refreshed.photoIDs.count == 7)
        #expect(refreshed.style == .film && refreshed.note == "Ours")
        #expect(refreshed.coverAssetID == nil, "the chosen cover is gone, so the best photo takes over")
    }

    // MARK: - Trips elsewhere

    @Test("Trips are a source for collages and stories too")
    func tripSource() throws {
        let library = fixture.library
        let photos = library.initialPhotos(for: .trip(CreationFixture.tripID), limit: 6)
        #expect(photos.count == 6)
        #expect(photos.contains { $0.hasPrefix("kas") } && photos.contains { $0.hasPrefix("kekova") })
        #expect(library.facts(for: .trip(CreationFixture.tripID), photos: photos).title == .named("Kaş"))
        #expect(library.visibleTrips.map(\.id) == [CreationFixture.tripID])
        let story = try StorySequenceBuilder(library: library).sequence(for: .trip(CreationFixture.tripID)).get()
        #expect((3...6).contains(story.cards.count))
    }
}

@Suite("Memory Book editing")
struct MemoryBookEditingTests {
    func book() -> MemoryBook {
        MemoryBook(createdAt: date(2026, 1, 1), source: .photos([]), photoIDs: ["a", "b", "c", "d", "e"], coverAssetID: "c")
    }

    @Test("Removing keeps a book a book")
    func remove() {
        var book = book()
        let ok1 = book.removePhoto("c")
        #expect(ok1)
        #expect(book.photoIDs == ["a", "b", "d", "e"])
        #expect(book.coverAssetID == nil, "the removed photo was the cover")
        let ok2 = book.removePhoto("a")
        #expect(!ok2, "four photos is the minimum")
        let ok3 = book.removePhoto("missing")
        #expect(!ok3)
    }

    @Test("Moving and replacing")
    func moveReplace() {
        var book = book()
        let ok4 = book.movePhoto("a", by: 1)
        #expect(ok4)
        #expect(book.photoIDs == ["b", "a", "c", "d", "e"])
        let ok5 = book.movePhoto("e", by: 1)
        #expect(!ok5)
        let ok6 = book.replacePhoto("c", with: "z")
        #expect(ok6)
        #expect(book.photoIDs[2] == "z" && book.coverAssetID == "z")
        let ok7 = book.replacePhoto("a", with: "b")
        #expect(!ok7, "no photo twice")
    }

    @Test("Choosing photos again keeps places and limits")
    func setPhotos() {
        var book = book()
        let ok8 = book.setPhotos(["e", "x", "a", "c", "y"])
        #expect(ok8)
        #expect(book.photoIDs == ["a", "c", "e", "x", "y"])
        let ok9 = book.setPhotos(["a", "b"])
        #expect(!ok9)
        #expect(book.photoIDs == ["a", "c", "e", "x", "y"])
        let ok10 = book.setPhotos((0..<80).map { "p\($0)" })
        #expect(ok10)
        #expect(book.photoIDs.count == BookLimits.maximumPhotos)
    }

    @Test("The cover is one of the book's photos; notes are trimmed")
    func coverAndNote() {
        var book = book()
        let ok11 = book.setCover("d")
        #expect(ok11)
        let ok12 = book.setCover("not-in-book")
        #expect(!ok12)
        #expect(book.coverAssetID == "d")
        let ok13 = book.setCover(nil)
        #expect(ok13)
        book.setNote("  For us.  ")
        #expect(book.note == "For us.")
        book.setNote("   ")
        #expect(book.note == nil)
    }
}
