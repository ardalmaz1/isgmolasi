import Foundation
import Testing
@testable import ReliveCore

@Suite("Creation sources and facts")
struct CreationLibraryTests {
    let fixture = CreationFixture.make()

    @Test("Only still, available photos from visible moments are usable")
    func usable() {
        var fixture = fixture
        fixture.unavailable = ["kas-3"]
        let library = fixture.library
        #expect(!library.isUsable("kekova-shot"), "screenshots are not memories to print")
        #expect(!library.isUsable("moda-video"), "videos can't go into a still image")
        #expect(!library.isUsable("kas-3"), "deleted photos can't be used")
        #expect(!library.isUsable("missing"), "unknown identifiers are ignored")
        #expect(library.isUsable("kas-0"))
        #expect(!library.visibleMoments.contains { $0.title.primary == "Spring Walk" }, "hidden moments stay hidden")
    }

    @Test("A collage from a moment preselects a spread of its photos, keeping the cover")
    func momentPreselection() {
        let library = fixture.library
        let kas = fixture.moment("kas")
        let picked = library.initialPhotos(for: .moment(kas.id), limit: 6)
        #expect(picked.count == 6)
        #expect(picked.contains(kas.heroAssetID!))
        #expect(Set(picked).isSubset(of: Set(kas.assetIDs)))
        #expect(picked == picked.sorted(by: library.chronologicalOrder))
        #expect(library.initialPhotos(for: .moment(kas.id), limit: 6) == picked, "deterministic")

        // A small moment gives all of its usable photos, never its screenshot.
        let kekova = library.initialPhotos(for: .moment(fixture.moment("kekova").id), limit: 6)
        #expect(kekova == ["kekova-0", "kekova-1", "kekova-2", "kekova-3"])
    }

    @Test("A hidden moment yields nothing")
    func hiddenMoment() {
        #expect(fixture.library.initialPhotos(for: .moment(fixture.moment("spring").id), limit: 6).isEmpty)
    }

    @Test("Chosen photos keep their order, drop duplicates and unusable items, and respect the limit")
    func chosenPhotos() {
        let ids = ["kas-2", "kas-1", "kas-2", "moda-video", "kekova-0"] + (0..<8).map { "coffee-\($0 % 6)" }
        let picked = fixture.library.initialPhotos(for: .photos(ids), limit: 6)
        #expect(picked == ["kas-2", "kas-1", "kekova-0", "coffee-0", "coffee-1", "coffee-2"])
    }

    @Test("Facts from one moment use its own title, dates and place")
    func momentFacts() {
        let kas = fixture.moment("kas")
        let facts = fixture.library.facts(for: .moment(kas.id), photos: Array(kas.assetIDs.prefix(3)))
        #expect(facts.title == .named("Kaş"))
        #expect(facts.place?.name == "Kaş")
        #expect(facts.dateSpan?.start == kas.startDate)
        #expect(facts.coordinate == Places.kas)
    }

    @Test("Photos from two moments of one trip are titled with the trip")
    func tripFacts() {
        let facts = fixture.library.facts(forPhotos: ["kas-0", "kekova-1"])
        #expect(facts.title == .named("Kaş"))
        #expect(facts.place?.name == "Kaş")
        #expect(facts.dateSpan == DateSpan(start: date(2025, 8, 6, 10), end: date(2025, 8, 7, 11, 10)))
    }

    @Test("Photos from unrelated moments get dates but no invented title or place")
    func mixedFacts() {
        let facts = fixture.library.facts(forPhotos: ["kas-0", "coffee-1"])
        #expect(facts.title == nil)
        #expect(facts.place == nil)
        #expect(facts.coordinate == nil)
        #expect(facts.dateSpan != nil)
    }

    @Test("A moment without a place prints no place")
    func noPlace() {
        let facts = fixture.library.facts(for: fixture.moment("afternoon"))
        #expect(facts.place == nil)
        #expect(facts.coordinate == nil)
        #expect(facts.title == .named("September Afternoon"))
    }

    @Test("Undated photos print no date")
    func undated() {
        let facts = fixture.library.facts(forPhotos: ["undated-0", "undated-1"])
        #expect(facts.dateSpan == nil)
    }

    @Test("Month and year sources are titled by the calendar")
    func calendarTitles() {
        let library = fixture.library
        #expect(library.facts(for: .month(MonthKey(year: 2025, month: 8)), photos: ["kas-0"]).title == .month(MonthKey(year: 2025, month: 8)))
        #expect(library.facts(for: .year(2025), photos: ["kas-0", "moda-0"]).title == .year(2025))
        // v0.3.1: one photo (or one month) of a year is not "Our 2025".
        #expect(library.facts(for: .year(2025), photos: ["kas-0"]).title == .named("Kaş"))
    }
}

@Suite("Monthly Recap")
struct MonthlyRecapTests {
    let fixture = CreationFixture.make()

    @Test("Lists months with visible dated moments, newest first")
    func months() {
        let months = MonthlyRecapBuilder(library: fixture.library).availableMonths()
        #expect(months == [MonthKey(year: 2026, month: 4), MonthKey(year: 2025, month: 9), MonthKey(year: 2025, month: 8)])
    }

    @Test("Counts only what is in the month")
    func counting() {
        let recap = MonthlyRecapBuilder(library: fixture.library).recap(for: MonthKey(year: 2025, month: 9))
        #expect(recap.moments.map(\.title.primary) == ["Moda Evening", "September Afternoon"])
        #expect(recap.statistics.momentCount == 2)
        #expect(recap.statistics.memoryCount == 7, "4 photos + 1 video + 2 photos")
        #expect(recap.statistics.placeCount == 1)
        #expect(recap.places.map(\.name) == ["Kadıköy"])
        #expect(recap.chapters.isEmpty)
        #expect(recap.isSufficient)
        let highlights = recap.highlights(limit: 4)
        #expect(highlights.count == 4)
        #expect(highlights.contains { $0.hasPrefix("moda") } && highlights.contains { $0.hasPrefix("afternoon") }, "covers both moments")
        #expect(!highlights.contains("moda-video"))
    }

    @Test("Uses calendar months in the user's time zone, at the edges too")
    func monthEdges() {
        var fixture = fixture
        // 23:30 on Aug 31 local time is still August, even though it is September 1 in some zones.
        let edge = makeAsset("edge-0", at: date(2025, 8, 31, 23, 30))
        fixture.assets[edge.id] = edge
        fixture.story.moments.append(Moment(
            id: CreationFixture.momentID("edge"), kind: .event, assetIDs: [edge.id], featuredAssetIDs: [edge.id],
            startDate: edge.creationDate, endDate: edge.creationDate, title: MomentTitle(primary: "Late")
        ))
        let builder = MonthlyRecapBuilder(library: fixture.library)
        #expect(builder.recap(for: MonthKey(year: 2025, month: 8)).moments.contains { $0.title.primary == "Late" })
        #expect(!builder.recap(for: MonthKey(year: 2025, month: 9)).moments.contains { $0.title.primary == "Late" })
    }

    @Test("Trips appear in the month they touch")
    func trips() {
        let recap = MonthlyRecapBuilder(library: fixture.library).recap(for: MonthKey(year: 2025, month: 8))
        #expect(recap.chapters.map(\.id) == [CreationFixture.tripID])
        #expect(recap.statistics.chapterCount == 1)
        #expect(recap.statistics.memoryCount == 13, "the screenshot is still a memory in the story's own count")
    }

    @Test("Hidden moments and empty months produce no recap content")
    func emptyAndHidden() {
        let builder = MonthlyRecapBuilder(library: fixture.library)
        let march = builder.recap(for: MonthKey(year: 2026, month: 3))
        #expect(march.moments.isEmpty)
        #expect(!march.isSufficient)
        #expect(march.highlights(limit: 6).isEmpty)
        let never = builder.recap(for: MonthKey(year: 2019, month: 1))
        #expect(never.statistics == .zero)
    }

    @Test("A month with too few memories is marked insufficient")
    func insufficient() {
        var fixture = fixture
        fixture.unavailable = ["moda-0", "moda-1", "moda-2", "moda-3", "moda-video"]
        let recap = MonthlyRecapBuilder(library: fixture.library).recap(for: MonthKey(year: 2025, month: 9))
        #expect(recap.statistics.memoryCount == 2)
        #expect(!recap.isSufficient)
    }
}

@Suite("Our Year")
struct YearInReviewTests {
    let fixture = CreationFixture.make()

    @Test("Lists years with visible dated moments, newest first")
    func years() {
        #expect(YearInReviewBuilder(library: fixture.library).availableYears() == [2026, 2025])
    }

    @Test("A year holds only its own months, in order, with trips where they began")
    func yearContent() {
        let review = YearInReviewBuilder(library: fixture.library).review(for: 2025)
        #expect(review.months.map(\.month.month) == [8, 9])
        #expect(review.months[0].chapters.map(\.id) == [CreationFixture.tripID])
        #expect(review.months[1].chapters.isEmpty)
        #expect(review.statistics.momentCount == 4)
        #expect(review.statistics.chapterCount == 1)
        #expect(review.isSufficient)
        #expect(review.firstMoment?.title.primary == "Kaş")
        #expect(review.lastMoment?.title.primary == "September Afternoon")
        #expect(review.months.allSatisfy { $0.highlights.count <= 4 && !$0.highlights.isEmpty })
        let highlights = review.highlights(limit: 6)
        #expect(highlights.contains { $0.hasPrefix("kas") || $0.hasPrefix("kekova") })
        #expect(highlights.contains { $0.hasPrefix("moda") || $0.hasPrefix("afternoon") })
    }

    @Test("Hidden moments are left out of the year")
    func hidden() {
        let review = YearInReviewBuilder(library: fixture.library).review(for: 2026)
        #expect(review.moments.map(\.title.primary) == ["Coffee"])
        #expect(review.months.map(\.month.month) == [4])
        #expect(!review.isSufficient, "one moment is not a year in review")
    }

    @Test("Undated moments belong to no year")
    func undated() {
        let years = YearInReviewBuilder(library: fixture.library).availableYears()
        #expect(!years.contains(2000))
    }
}
