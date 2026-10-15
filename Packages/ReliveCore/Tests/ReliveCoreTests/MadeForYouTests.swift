import Foundation
import Testing
@testable import ReliveCore

/// Made for You fixtures, built on `IntelligenceFixture`. "Now" is October 14, 2026, noon.
enum MadeForYouFixture {
    static let now = date(2026, 10, 14, 12)

    /// `count` distinct photos taken `spacing` seconds apart from `start`.
    static func shots(_ prefix: String, _ count: Int, start: Date, spacing: TimeInterval = 900, location: GeoCoordinate? = nil, lookOffset: Int, favorite: Bool = false) -> [IntelligenceFixture.Shot] {
        var result: [IntelligenceFixture.Shot] = []
        for index in 0..<count {
            let when = start.addingTimeInterval(Double(index) * spacing)
            let quality = 0.45 + Double(index % 4) / 10
            let look = IntelligenceFixture.look(lookOffset + index)
            result.append(IntelligenceFixture.Shot(id: "\(prefix)-\(index)", date: when, location: location,
                                                   portrait: index % 3 != 0, favorite: favorite && index == 0, look: look, quality: quality))
        }
        return result
    }

    static func moment(_ key: String, _ title: String, _ count: Int, start: Date, place: String? = nil, location: GeoCoordinate? = nil, trip: String? = nil, look: Int, favorite: Bool = false) -> IntelligenceFixture.MomentSpec {
        .init(key: key, title: title, shots: shots(key, count, start: start, location: location, lookOffset: look, favorite: favorite), place: place, trip: trip)
    }

    static func engine(_ fixture: IntelligenceFixture, history: SuggestionHistory = SuggestionHistory(), hemisphere: PeriodDescriptor.Hemisphere? = nil) -> MadeForYouEngine {
        MadeForYouEngine(library: fixture.library, now: now, history: history, hemisphere: hemisphere)
    }
}

@Suite("Made for You: kinds")
struct MadeForYouKindTests {
    typealias F = MadeForYouFixture

    @Test func aRealAnniversaryWithEnoughPhotos() {
        let fixture = IntelligenceFixture(moments: [F.moment("anni", "Kaş", 4, start: date(2025, 10, 14, 15), place: "Kaş", look: 0)])
        let suggestions = F.engine(fixture).anniversaries()
        let anniversary = try? #require(suggestions.first)
        #expect(anniversary?.kind == .anniversary)
        #expect(anniversary?.eyebrow == "A year ago today")
        #expect(anniversary?.title == "Kaş")
        #expect(anniversary?.subtitle == "4 memories · October 14, 2025")
        #expect(anniversary?.creation == .collage)
        #expect(anniversary?.source == .moment(IntelligenceFixture.momentID("anni")))
    }

    @Test func oneMeaninglessPhotoIsNoAnniversaryButAFavoritePairIs() {
        let single = IntelligenceFixture(moments: [F.moment("one", "October Afternoon", 1, start: date(2025, 10, 14, 15), look: 0)])
        #expect(F.engine(single).anniversaries().isEmpty)
        let plainPair = IntelligenceFixture(moments: [F.moment("pair", "October Afternoon", 2, start: date(2024, 10, 13, 15), look: 0)])
        #expect(F.engine(plainPair).anniversaries().isEmpty)
        let favoritePair = IntelligenceFixture(moments: [F.moment("pair", "October Afternoon", 2, start: date(2024, 10, 13, 15), look: 0, favorite: true)])
        let suggestion = F.engine(favoritePair).anniversaries().first
        #expect(suggestion?.eyebrow == "2 years ago this week")
    }

    @Test func oldMemoriesRemainEligible() {
        let fixture = IntelligenceFixture(moments: [F.moment("old", "Inverness", 5, start: date(2012, 10, 14, 11), place: "Inverness", look: 0)])
        #expect(F.engine(fixture).anniversaries().first?.eyebrow == "14 years ago today")
    }

    @Test func aStrongMonthAndAWeakOne() {
        let strong = IntelligenceFixture(moments: [
            F.moment("o1", "October Morning", 5, start: date(2026, 10, 2, 9), look: 0),
            F.moment("o2", "October Evening", 5, start: date(2026, 10, 9, 19), look: 10),
        ])
        let month = F.engine(strong).months(index: TemporalIndex(library: strong.library)).first
        #expect(month?.kind == .monthRecap)
        #expect(month?.title == "Your October")
        #expect(month?.subtitle == "10 memories · 2 moments")
        #expect(month?.creation == .monthlyRecap)
        #expect(month?.source == .month(MonthKey(year: 2026, month: 10)))

        let weak = IntelligenceFixture(moments: [F.moment("o1", "October Morning", 5, start: date(2026, 10, 2, 9), look: 0)])
        #expect(F.engine(weak).months(index: TemporalIndex(library: weak.library)).isEmpty)
    }

    @Test func aYearOnceItIsOne() {
        let fixture = IntelligenceFixture(moments: [
            F.moment("jan", "January Walk", 4, start: date(2026, 1, 10, 12), look: 0),
            F.moment("may", "May Afternoon", 4, start: date(2026, 5, 3, 15), look: 10),
            F.moment("aug", "August Evening", 4, start: date(2026, 8, 20, 19), look: 20),
        ])
        let year = F.engine(fixture).years(index: TemporalIndex(library: fixture.library)).first
        #expect(year?.kind == .yearRecap)
        #expect(year?.title == "Our 2026")
        #expect(year?.subtitle == "12 memories · 3 months")
        #expect(year?.creation == .yearInReview)
    }

    @Test func aTripTheStoryKnows() {
        let trip = IntelligenceFixture.mixedTrip()
        let suggestion = F.engine(trip).trips().first
        #expect(suggestion?.kind == .trip)
        #expect(suggestion?.title == "Three days in Kaş & Kekova.")
        #expect(suggestion?.subtitle == "30 memories · August 2025")
        // Thirty distinct photos over three days: varied enough for a film.
        #expect(suggestion?.creation == .movie)
        #expect(suggestion?.id == "trip:\(IntelligenceFixture.momentID("d1").uuidString)")

        // Without a trip in the story, the same photos are never called a trip.
        var noTrip = trip
        for index in noTrip.moments.indices { noTrip.moments[index].trip = nil }
        #expect(F.engine(noTrip).trips().isEmpty)
    }

    @Test func aPlaceAcrossTheYears() {
        let fixture = IntelligenceFixture(moments: [
            F.moment("b1", "Bergama", 3, start: date(2023, 5, 1, 12), place: "Bergama", look: 0),
            F.moment("b2", "Bergama", 3, start: date(2024, 6, 1, 12), place: "Bergama", look: 10),
            F.moment("b3", "Bergama", 3, start: date(2026, 4, 1, 12), place: "Bergama", look: 20),
        ])
        let place = F.engine(fixture).places().first
        #expect(place?.title == "Bergama through the years")
        #expect(place?.subtitle == "2023 – 2026 · 9 memories")
        #expect(place?.creation == .story)
    }

    @Test func seasonsOnlyWithAKnownHemisphere() {
        func summer(location: GeoCoordinate?) -> IntelligenceFixture {
            IntelligenceFixture(moments: [
                F.moment("jun", "June Evening", 5, start: date(2025, 6, 12, 19), location: location, look: 0),
                F.moment("jul", "July Morning", 5, start: date(2025, 7, 8, 9), location: location, look: 10),
                F.moment("aug", "August Afternoon", 5, start: date(2025, 8, 15, 15), location: location, look: 20),
            ])
        }
        let unlocated = summer(location: nil)
        #expect(F.engine(unlocated).seasons(index: TemporalIndex(library: unlocated.library)).isEmpty, "no guess without a hemisphere")

        let northern = summer(location: Places.kas)
        let seasons = F.engine(northern).seasons(index: TemporalIndex(library: northern.library))
        #expect(seasons.map(\.title) == ["Summer 2025"])

        let southern = F.engine(unlocated, hemisphere: .southern).seasons(index: TemporalIndex(library: unlocated.library))
        #expect(southern.map(\.title) == ["Winter 2025"], "June–August is winter in the south")

        // Photos on both sides of the equator: no hemisphere, no season.
        var mixed = summer(location: Places.kas)
        mixed.moments[0].shots = mixed.moments[0].shots.map { var shot = $0; shot.location = GeoCoordinate(latitude: -33.86, longitude: 151.2); return shot }
        #expect(F.engine(mixed).seasons(index: TemporalIndex(library: mixed.library)).isEmpty)
    }
}

@Suite("Made for You: selection")
struct MadeForYouSelectionTests {
    typealias F = MadeForYouFixture

    /// A trip in last month: the month and the trip are mostly the same memories.
    static func overlapping() -> IntelligenceFixture {
        IntelligenceFixture(moments: [
            F.moment("s1", "Kaş", 6, start: date(2026, 9, 10, 10), place: "Kaş", trip: "Kaş", look: 0),
            F.moment("s2", "Kaş Harbour", 6, start: date(2026, 9, 11, 10), place: "Kaş", trip: "Kaş", look: 10),
        ])
    }

    @Test func overlappingSuggestionsKeepTheStrongerOne() {
        let suggestions = F.engine(Self.overlapping()).suggestions()
        let kinds = suggestions.map(\.kind)
        #expect(kinds.contains(.monthRecap) != kinds.contains(.trip), "one of them, not both: \(kinds)")
        for (i, a) in suggestions.enumerated() {
            for b in suggestions.dropFirst(i + 1) {
                #expect(MadeForYouEngine.overlap(a.coverage, b.coverage) <= 0.5)
            }
        }
    }

    @Test func weakLibrariesSuggestNothing() {
        let tiny = IntelligenceFixture(moments: [F.moment("t", "March Afternoon", 2, start: date(2026, 3, 3, 15), look: 0)])
        #expect(F.engine(tiny).suggestions().isEmpty, "empty space is better than a bad suggestion")
        #expect(F.engine(IntelligenceFixture(moments: [])).suggestions().isEmpty)
    }

    @Test func hiddenMemoriesNeverAppear() {
        var fixture = IntelligenceFixture.mixedTrip()
        for index in fixture.moments.indices { fixture.moments[index].hidden = true }
        #expect(F.engine(fixture).suggestions().isEmpty)
        fixture.moments[2].hidden = false
        let suggestions = F.engine(fixture).suggestions()
        #expect(suggestions.allSatisfy { $0.assetIDs.allSatisfy { $0.hasPrefix("d3") } })
    }

    @Test func undatedMemoriesNeverBecomeAMonthOrAnniversary() {
        let shots = (0..<12).map { IntelligenceFixture.Shot(id: "u-\($0)", date: nil, look: IntelligenceFixture.look($0)) }
        let fixture = IntelligenceFixture(moments: [.init(key: "u", title: "", shots: shots)])
        let suggestions = F.engine(fixture).suggestions()
        #expect(!suggestions.contains { [.anniversary, .throwback, .monthRecap, .yearRecap, .season].contains($0.kind) })
    }

    @Test func favoritesRankHigher() {
        let plain = IntelligenceFixture(moments: [F.moment("a", "Kaş", 4, start: date(2025, 10, 14, 15), look: 0)])
        let favorite = IntelligenceFixture(moments: [F.moment("a", "Kaş", 4, start: date(2025, 10, 14, 15), look: 0, favorite: true)])
        let plainQuality = F.engine(plain).anniversaries().first?.quality ?? 0
        let favoriteQuality = F.engine(favorite).anniversaries().first?.quality ?? 0
        #expect(favoriteQuality > plainQuality)
    }

    @Test func duplicateCopiesAreNotPartOfASuggestion() {
        var fixture = IntelligenceFixture(moments: [F.moment("d", "Kaş", 5, start: date(2025, 10, 14, 15), look: 0)])
        fixture.moments[0].shots.append(.init(id: "copy", date: date(2025, 10, 20, 9), look: IntelligenceFixture.look(0), megapixelsScale: 0.1))
        fixture.moments[0].duplicates = ["copy"]
        let suggestion = F.engine(fixture).anniversaries().first
        #expect(suggestion != nil)
        #expect(suggestion?.assetIDs.contains("copy") == false)
    }

    @Test func mixedYearsGetHonestTitles() {
        let fixture = IntelligenceFixture.mixedYears()
        for suggestion in F.engine(fixture).suggestions() {
            #expect(!suggestion.title.contains("September Together"))
        }
    }

    @Test func everyWordIsFactual() {
        let fixtures = [IntelligenceFixture.mixedTrip(), .mixedYears(), MadeForYouSelectionTests.overlapping()]
        for fixture in fixtures {
            for suggestion in F.engine(fixture).suggestions() {
                for text in [suggestion.eyebrow, suggestion.title, suggestion.subtitle] {
                    #expect(FactualTextPolicy.isFactual(text), "\(text)")
                }
            }
        }
    }
}

@Suite("Made for You: history and identity")
struct MadeForYouHistoryTests {
    typealias F = MadeForYouFixture

    @Test func dismissedStaysAwayThenMayReturn() throws {
        let fixture = IntelligenceFixture.mixedTrip(year: 2026)
        let first = try #require(F.engine(fixture).suggestions().first)
        var history = SuggestionHistory()
        history.recordDismissed(first.id, now: F.now)
        #expect(!F.engine(fixture, history: history).suggestions().map(\.id).contains(first.id))
        let later = MadeForYouEngine(library: fixture.library, now: F.now.addingTimeInterval(91 * 86_400), history: history)
        #expect(!history.isSuppressed(first.id, now: later.now))
    }

    @Test func madeSuggestionsStayAwayAndShownOnesRotate() throws {
        let fixture = IntelligenceFixture.mixedTrip(year: 2026)
        let first = try #require(F.engine(fixture).suggestions().first)
        var history = SuggestionHistory()
        history.recordCreated(first.id, now: F.now)
        #expect(history.isSuppressed(first.id, now: F.now.addingTimeInterval(30 * 86_400)))

        var shown = SuggestionHistory()
        for day in 0..<5 {
            shown.recordShown(first.id, now: F.now.addingTimeInterval(Double(day) * 86_400), calendar: testCalendar)
            shown.recordShown(first.id, now: F.now.addingTimeInterval(Double(day) * 86_400 + 60), calendar: testCalendar)
        }
        #expect(shown.entries[first.id]?.shownDays == 5, "counted once per day")
        #expect(shown.rotationPenalty(first.id) > 0)
        shown.recordOpened(first.id, now: F.now)
        #expect(shown.rotationPenalty(first.id) == 0, "opening it isn't ignoring it")
    }

    @Test func historyPersists() throws {
        var history = SuggestionHistory()
        history.recordShown("month:2026-9", now: F.now, calendar: testCalendar)
        history.recordDismissed("trip:x", now: F.now)
        let decoded = try JSONDecoder().decode(SuggestionHistory.self, from: JSONEncoder().encode(history))
        #expect(decoded == history)
    }

    @Test func identitiesAreStable() {
        let fixture = IntelligenceFixture.mixedTrip(year: 2026)
        let a = F.engine(fixture).suggestions().map(\.id)
        let b = F.engine(fixture).suggestions().map(\.id)
        #expect(a == b)
        #expect(!a.isEmpty)
    }
}
