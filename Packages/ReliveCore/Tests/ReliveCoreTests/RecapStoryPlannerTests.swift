import Foundation
import Testing
@testable import ReliveCore

/// Recap fixtures on `IntelligenceFixture` (UTC+3 calendar).
enum RecapFixture {
    typealias Shot = IntelligenceFixture.Shot
    typealias Spec = IntelligenceFixture.MomentSpec

    /// `count` distinct photos from `start`, `spacing` seconds apart.
    static func moment(_ key: String, _ title: String, start: Date, count: Int, spacing: TimeInterval = 1_800, place: String? = nil, trip: String? = nil,
                       look: Int, favorites: Set<Int> = [], faces: Set<Int> = [], similarFirst: Int = 0) -> Spec {
        var shots: [Shot] = []
        for index in 0..<count {
            let when = start.addingTimeInterval(Double(index) * (index < similarFirst ? 20 : spacing))
            let vector: [Float] = index < similarFirst ? IntelligenceFixture.near(look, drift: Float(index) * 0.02) : IntelligenceFixture.look(look + index)
            let quality = 0.45 + Double(index % 4) / 10
            shots.append(Shot(id: "\(key)-\(index)", date: when, portrait: index % 3 != 0, favorite: favorites.contains(index),
                              look: vector, faces: faces.contains(index) ? 2 : 0, quality: quality))
        }
        return Spec(key: key, title: title, shots: shots, place: place, trip: trip)
    }

    /// The acceptance month: September 2026 — 43 memories, 6 moments, 7 active days, 3 known
    /// places, 1 trip (Kaş, 3 days), 4 favorites, a few near-identical shots.
    static func september2026() -> IntelligenceFixture {
        IntelligenceFixture(moments: [
            moment("m1", "Bergama", start: date(2026, 9, 3, 10), count: 6, place: "Bergama", look: 0, favorites: [1], faces: [0, 2, 4]),
            moment("m2", "Bergama", start: date(2026, 9, 10, 15), count: 5, place: "Bergama", look: 8, faces: [1]),
            moment("m3", "Kaş", start: date(2026, 9, 12, 9), count: 10, place: "Kaş", trip: "Kaş", look: 16, favorites: [5], similarFirst: 3),
            moment("m4", "Kaş Harbour", start: date(2026, 9, 13, 20), count: 9, place: "Kaş", trip: "Kaş", look: 28, faces: [2, 3]),
            moment("m5", "Bergama", start: date(2026, 9, 18, 11), count: 8, place: "Bergama", look: 40, favorites: [2], faces: [5]),
            moment("m6", "Aliağa", start: date(2026, 9, 27, 17), count: 5, place: "Aliağa", look: 50, favorites: [0]),
        ])
    }

    /// The acceptance year: 2026 — 126 memories, 14 moments, 5 places, 2 trips, 8 active months,
    /// 9 favorites.
    static func year2026() -> IntelligenceFixture {
        let months = [1, 2, 3, 5, 6, 8, 9, 11]
        let places = ["Bergama", "Aliağa", "Kaş", "İzmir", "Foça"]
        var specs: [Spec] = []
        var favoritesLeft = 9
        var photosLeft = 126
        for (monthIndex, month) in months.enumerated() {
            let momentsThisMonth = monthIndex < 6 ? 2 : 1
            for part in 0..<momentsThisMonth {
                let number = specs.count
                let remainingMoments = 14 - number
                let count = number == 13 ? photosLeft : 9
                photosLeft -= count
                _ = remainingMoments
                let place = places[number % places.count]
                let trip: String? = month == 3 ? "Foça" : month == 8 ? "Kaş" : nil
                let favorites: Set<Int> = favoritesLeft > 0 ? [0] : []
                if favoritesLeft > 0 { favoritesLeft -= 1 }
                specs.append(moment("y\(number)", "\(place) \(month)", start: date(2026, month, 4 + part * 9, 10), count: count,
                                    place: trip ?? place, trip: trip, look: number * 9 % 60, favorites: favorites, faces: [1, 4]))
            }
        }
        return IntelligenceFixture(moments: specs)
    }

    static func planner(_ fixture: IntelligenceFixture) -> RecapStoryPlanner {
        RecapStoryPlanner(library: fixture.library)
    }

    static func month(_ year: Int, _ month: Int) -> RecapPeriod { .month(MonthKey(year: year, month: month)) }

    /// Every photo a plan shows.
    static func photos(of plan: RecapPlan) -> Set<AssetID> {
        Set(plan.chapters.flatMap { [$0.hero].compactMap { $0 } + $0.photos + $0.entries.compactMap(\.photo) } + plan.sharePhotos)
    }
}

@Suite("Recap planner: Monthly Recap 2.0")
struct MonthlyRecapPlanTests {
    @Test func acceptanceMonth() throws {
        let fixture = RecapFixture.september2026()
        let plan = RecapFixture.planner(fixture).plan(RecapFixture.month(2026, 9))
        #expect(plan.isRich)
        #expect((5...10).contains(plan.chapters.count), "\(plan.chapters.map(\.kind))")
        #expect(plan.chapters.first?.kind == .opening)
        #expect(plan.chapters.last?.kind == .closing)
        #expect(plan.chapters.first?.hero != nil, "a hero chosen by Memory Intelligence")

        let insights = plan.insights
        #expect(insights.memoryCount == 43)
        #expect(insights.momentCount == 6)
        #expect(insights.activeDays == 7)
        #expect(insights.places.map(\.name) == ["Bergama", "Kaş", "Aliağa"])
        #expect(insights.tripCount == 1)
        #expect(insights.favoriteCount == 4)
        #expect(insights.mostRepresentedPlace?.place.name == "Bergama")

        let opening = try #require(plan.chapters.first)
        #expect(opening.text.title == "September, together.")
        #expect(opening.text.detail == "43 memories · 6 moments · 3 places")
        let first = try #require(plan.chapters.first { $0.kind == .firstMemory })
        #expect(first.text.title == "The month began here.")
        #expect(first.text.detail == "September 3 · Bergama")
        let trip = try #require(plan.chapters.first { $0.kind == .tripHighlight })
        #expect(trip.text.title == "Three days in Kaş.")
        #expect(trip.text.detail == "September 12–14, 2026 · 19 memories")
        let place = try #require(plan.chapters.first { $0.kind == .placeHighlight })
        #expect(place.text.title == "Bergama, again.")
        #expect(place.text.detail == "3 moments on 3 different days")
        let closing = try #require(plan.chapters.last)
        #expect(closing.text.title == "That was your September.")
        #expect(closing.text.detail == "43 memories · 6 moments · 3 places")

        // The timeline is in order, each date its own moment's.
        let timeline = try #require(plan.chapters.first { $0.kind == .timeline })
        #expect(timeline.entries.map(\.title) == ["September 3", "September 10", "September 12", "September 13", "September 18", "September 27"])

        // Only September 2026; heroes never repeat; near-identical shots aren't stacked.
        let shown = RecapFixture.photos(of: plan)
        for id in shown {
            let when = try #require(fixture.library.assets[id]?.creationDate)
            #expect(MonthKey(date: when, calendar: testCalendar) == MonthKey(year: 2026, month: 9))
        }
        let heroes = plan.chapters.compactMap(\.hero)
        #expect(heroes.count == Set(heroes).count)
        let grid = try #require(plan.chapters.first { $0.kind == .visualGrid })
        #expect(grid.photos.filter { ["m3-0", "m3-1", "m3-2"].contains($0) }.count <= 1)
        #expect(grid.text.title == "September in \(grid.photos.count) frames.")

        // Creation and share sources.
        #expect(plan.creationSource == .month(MonthKey(year: 2026, month: 9)))
        #expect(!plan.sharePhotos.isEmpty)
    }

    @Test func everyWordIsFactual() {
        for fixture in [RecapFixture.september2026(), RecapFixture.year2026()] {
            for period in [RecapFixture.month(2026, 9), .year(2026)] {
                for chapter in RecapFixture.planner(fixture).plan(period).chapters {
                    #expect(ValidatedEditorialTextProvider.isAcceptable(chapter.text, for: chapter.facts), "\(chapter.text)")
                }
            }
        }
    }

    @Test func sparseMonthsAreNotPadded() throws {
        let fixture = IntelligenceFixture(moments: [RecapFixture.moment("s", "September Walk", start: date(2026, 9, 5, 12), count: 5, look: 0)])
        let plan = RecapFixture.planner(fixture).plan(RecapFixture.month(2026, 9))
        #expect(!plan.isRich)
        #expect(plan.chapters.map(\.kind) == [.compactSummary])
        let compact = try #require(plan.chapters.first)
        #expect(compact.text.title == "September was a quiet one in Yuvi.")
        #expect(compact.text.detail == "5 memories · 1 moment")
    }

    @Test func mixedYearsNeverContaminateAMonthOrYear() throws {
        let fixture = IntelligenceFixture(moments: [
            RecapFixture.moment("apr25", "April", start: date(2025, 4, 12, 10), count: 8, look: 0),
            RecapFixture.moment("may25", "May", start: date(2025, 5, 3, 10), count: 5, look: 10),
            RecapFixture.moment("sep25a", "September", start: date(2025, 9, 10, 10), count: 6, look: 20),
            RecapFixture.moment("sep25b", "September", start: date(2025, 9, 14, 10), count: 6, look: 30),
            RecapFixture.moment("jan26", "January", start: date(2026, 1, 5, 10), count: 6, look: 40),
            RecapFixture.moment("sep26a", "September", start: date(2026, 9, 18, 10), count: 5, look: 50),
            RecapFixture.moment("sep26b", "September", start: date(2026, 9, 20, 10), count: 4, look: 56),
            RecapFixture.moment("oct26", "October", start: date(2026, 10, 4, 10), count: 4, look: 60),
        ])
        let planner = RecapFixture.planner(fixture)
        func years(_ plan: RecapPlan) -> Set<Int> {
            Set(RecapFixture.photos(of: plan).compactMap { fixture.library.assets[$0]?.creationDate.map { testCalendar.component(.year, from: $0) } })
        }
        let sep25 = planner.plan(RecapFixture.month(2025, 9))
        #expect(RecapFixture.photos(of: sep25).allSatisfy { $0.hasPrefix("sep25") })
        #expect(sep25.insights.memoryCount == 12)
        let sep26 = planner.plan(RecapFixture.month(2026, 9))
        #expect(RecapFixture.photos(of: sep26).allSatisfy { $0.hasPrefix("sep26") })
        #expect(sep26.insights.memoryCount == 9)
        #expect(years(planner.plan(.year(2025))) == [2025])
        #expect(years(planner.plan(.year(2026))) == [2026])
        #expect(planner.plan(.year(2025)).insights.memoryCount == 25)
        #expect(planner.plan(.year(2026)).insights.memoryCount == 19)
    }

    @Test func burstsDontFillTheFrames() {
        let fixture = IntelligenceFixture(moments: [
            RecapFixture.moment("b1", "Selfies", start: date(2026, 9, 3, 18), count: 12, look: 0, similarFirst: 12),
            RecapFixture.moment("b2", "Walk", start: date(2026, 9, 10, 10), count: 6, look: 20),
            RecapFixture.moment("b3", "Dinner", start: date(2026, 9, 20, 20), count: 6, look: 30),
        ])
        let plan = RecapFixture.planner(fixture).plan(RecapFixture.month(2026, 9))
        let grid = plan.chapters.first { $0.kind == .visualGrid }
        #expect((grid?.photos.filter { $0.hasPrefix("b1") }.count ?? 0) <= 1, "one selfie stands for the burst")
    }

    /// Enough memories, but all near-identical in one moment: only an opening and a closing would
    /// be true, so it is told as one compact page rather than a two-page "recap".
    @Test func aThinMonthIsCompactNotPadded() {
        let fixture = IntelligenceFixture(moments: [RecapFixture.moment("a", "October Night", start: date(2026, 10, 14, 20), count: 24, look: 0)])
        let plan = RecapFixture.planner(fixture).plan(RecapFixture.month(2026, 10))
        #expect(!plan.isRich, "\(plan.chapters.map(\.kind))")
        #expect(plan.chapters.map(\.kind) == [.compactSummary])
        #expect(plan.chapters.first?.text.detail == "24 memories · 1 moment")
    }

    @Test func almostNoLocationMeansNoPlaceChapters() {
        let fixture = IntelligenceFixture(moments: [
            RecapFixture.moment("a", "Morning", start: date(2026, 9, 3, 9), count: 5, look: 0),
            RecapFixture.moment("b", "Evening", start: date(2026, 9, 9, 19), count: 5, look: 10),
            RecapFixture.moment("c", "Afternoon", start: date(2026, 9, 21, 15), count: 5, look: 20, faces: []),
        ])
        let plan = RecapFixture.planner(fixture).plan(RecapFixture.month(2026, 9))
        #expect(plan.isRich)
        #expect(!plan.chapters.contains { [.places, .placeHighlight, .tripHighlight].contains($0.kind) })
        #expect(plan.chapters.first?.text.detail == "15 memories · 3 moments", "no '0 places'")
        #expect(plan.chapters.first { $0.kind == .firstMemory }?.text.detail == "September 3", "no invented place")
    }

    @Test func undatedHiddenAndMissingStayOut() {
        var fixture = RecapFixture.september2026()
        fixture.moments.append(.init(key: "u", title: "", shots: (0..<5).map { IntelligenceFixture.Shot(id: "u-\($0)", date: nil, look: IntelligenceFixture.look(70 + $0)) }))
        fixture.moments[5].hidden = true
        fixture.unavailable = ["m1-0"]
        let plan = RecapFixture.planner(fixture).plan(RecapFixture.month(2026, 9))
        let shown = RecapFixture.photos(of: plan)
        #expect(!shown.contains { $0.hasPrefix("u-") || $0.hasPrefix("m6") || $0 == "m1-0" })
        #expect(!plan.insights.places.map(\.name).contains("Aliağa"), "the hidden moment's place isn't counted")
    }

    @Test func favoritesAndCoversInfluenceHeroes() {
        var fixture = RecapFixture.september2026()
        fixture.moments[0].userCover = "m1-3"
        let plan = RecapFixture.planner(fixture).plan(RecapFixture.month(2026, 9))
        let favorites = plan.chapters.first { $0.kind == .favoriteHighlight }
        #expect(favorites?.text.detail == "4 favorites")
        let favoritePhotos = Set(favorites?.photos ?? [])
        #expect(favoritePhotos.isSubset(of: ["m1-1", "m3-5", "m5-2", "m6-0"]))
    }

    @Test func plansAreDeterministicAndOldYearsAreNotPenalized() {
        let fixture = RecapFixture.september2026()
        #expect(RecapFixture.planner(fixture).plan(RecapFixture.month(2026, 9)) == RecapFixture.planner(fixture).plan(RecapFixture.month(2026, 9)))
        // The same month fourteen years earlier gets the same chapters.
        var old = fixture
        for m in old.moments.indices {
            old.moments[m].shots = old.moments[m].shots.map { var shot = $0; shot.date = shot.date.map { testCalendar.date(byAdding: .year, value: -14, to: $0)! }; return shot }
        }
        let recent = RecapFixture.planner(fixture).plan(RecapFixture.month(2026, 9)).chapters.map(\.kind)
        let earlier = RecapFixture.planner(old).plan(RecapFixture.month(2012, 9)).chapters.map(\.kind)
        #expect(recent == earlier)
    }
}

@Suite("Recap planner: Our Year 2.0")
struct YearRecapPlanTests {
    @Test func acceptanceYear() throws {
        let fixture = RecapFixture.year2026()
        let plan = RecapFixture.planner(fixture).plan(.year(2026))
        #expect(plan.isRich)
        #expect((8...16).contains(plan.chapters.count), "\(plan.chapters.map(\.kind))")
        #expect(plan.insights.memoryCount == 126)
        #expect(plan.insights.momentCount == 14)
        #expect(plan.insights.places.count == 5)
        #expect(plan.insights.tripCount == 2)
        #expect(plan.insights.monthsRepresented.count == 8)
        #expect(plan.insights.favoriteCount == 9)

        #expect(plan.chapters.first?.text.title == "2026, together.")
        let first = try #require(plan.chapters.first { $0.kind == .firstMemory })
        #expect(first.hero == "y0-0", "the earliest 2026 memory")
        #expect(first.text.detail?.hasPrefix("January 4") == true)

        let months = try #require(plan.chapters.first { $0.kind == .monthByMonth })
        #expect(months.entries.map(\.title) == ["January", "February", "March", "May", "June", "August", "September", "November"], "in order, no empty months")
        #expect(plan.chapters.filter { $0.kind == .tripHighlight }.count == 2)
        let shown = RecapFixture.photos(of: plan)
        #expect(shown.allSatisfy { fixture.library.assets[$0]?.creationDate.map { testCalendar.component(.year, from: $0) } == 2026 })
        #expect(plan.chapters.last?.text.title == "That was your 2026.")
        #expect(plan.chapters.last?.text.detail == "126 memories · 14 moments · 5 places")
    }

    @Test func aYearWithThreeActiveMonths() {
        let fixture = IntelligenceFixture(moments: [
            RecapFixture.moment("a", "Spring", start: date(2026, 3, 3, 10), count: 4, look: 0),
            RecapFixture.moment("b", "Summer", start: date(2026, 7, 3, 10), count: 4, look: 10),
            RecapFixture.moment("c", "Autumn", start: date(2026, 10, 3, 10), count: 4, look: 20),
        ])
        let plan = RecapFixture.planner(fixture).plan(.year(2026))
        #expect(plan.isRich)
        #expect(plan.chapters.first { $0.kind == .monthByMonth }?.entries.count == 3)
    }

    @Test func aYearThatIsntOneYetIsCompact() {
        let fixture = IntelligenceFixture(moments: [RecapFixture.moment("a", "Spring", start: date(2026, 3, 3, 10), count: 12, look: 0)])
        let plan = RecapFixture.planner(fixture).plan(.year(2026))
        #expect(!plan.isRich)
        #expect(plan.chapters.first?.text.title == "Your 2026 is just getting started.")
    }

    @Test func diagnosticsHoldNoIdentifiers() {
        let plan = RecapFixture.planner(RecapFixture.september2026()).plan(RecapFixture.month(2026, 9))
        let line = plan.diagnosticsLine
        #expect(line.hasPrefix("recap_plan period=2026-09 rich=true memories=43"))
        #expect(!line.contains("m1-") && !line.contains("Bergama"))
    }
}

@Suite("Recap planner: editorial text contract")
struct EditorialTextTests {
    struct FakeAI: EditorialTextProviding {
        var reply: EditorialText
        func text(for facts: EditorialFacts) -> EditorialText { reply }
    }

    private let facts = EditorialFacts.monthOpening(monthName: "September", year: 2026, memories: 43, moments: 6, places: 3)

    @Test func aFeelingClaimFallsBackToTheFacts() {
        let provider = ValidatedEditorialTextProvider(candidate: FakeAI(reply: EditorialText(title: "Your happiest September")))
        #expect(provider.text(for: facts).title == "September, together.")
    }

    @Test func aMadeUpNumberFallsBackToTheFacts() {
        let provider = ValidatedEditorialTextProvider(candidate: FakeAI(reply: EditorialText(title: "September", detail: "50 memories")))
        #expect(provider.text(for: facts).detail == "43 memories · 6 moments · 3 places")
    }

    @Test func aFaithfulRephrasingIsKept() {
        let rephrased = EditorialText(eyebrow: "September 2026", title: "Our September.", detail: "43 memories across 6 moments")
        let provider = ValidatedEditorialTextProvider(candidate: FakeAI(reply: rephrased))
        #expect(provider.text(for: facts) == rephrased)
    }

    @Test func factsCarryNoPrivateData() throws {
        let plan = RecapFixture.planner(RecapFixture.september2026()).plan(RecapFixture.month(2026, 9))
        let json = String(data: try JSONEncoder().encode(plan.chapters.map(\.facts)), encoding: .utf8) ?? ""
        #expect(!json.contains("m1-"), "no photo identifiers")
        #expect(!json.contains("latitude"), "no coordinates")
    }
}
