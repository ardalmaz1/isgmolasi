import Foundation
import Testing
@testable import ReliveCore

@Suite("LocalMomentNamingService")
struct MomentNamingTests {
    let naming = LocalMomentNamingService(calendar: testCalendar)

    func event(_ start: Date, _ end: Date, place: String? = nil) -> MomentNamingContext {
        MomentNamingContext(kind: .event, start: start, end: end, place: place.map { PlaceName(name: $0) }, assetCount: 10)
    }

    @Test("A place gives 'Kaş • August 2025'")
    func placeAndMonth() {
        let title = naming.makeTitle(for: event(date(2025, 8, 6, 18), date(2025, 8, 6, 21), place: "Kaş"))
        #expect(title == MomentTitle(primary: "Kaş", secondary: "August 2025"))
        #expect(title.combined == "Kaş • August 2025")
    }

    @Test("At home, the time leads and the place steps back")
    func homeUsesTime() {
        var context = event(date(2025, 6, 12, 19), date(2025, 6, 12, 20), place: "Kadıköy")
        context.isAtHome = true
        #expect(naming.makeTitle(for: context) == MomentTitle(primary: "June Evening", secondary: "June 2025"))
    }

    @Test("Without a place, an evening is named after its month")
    func evening() {
        let title = naming.makeTitle(for: event(date(2024, 12, 12, 19), date(2024, 12, 12, 21)))
        #expect(title.primary == "December Evening")
    }

    @Test("A long Saturday without a place")
    func wholeWeekendDay() {
        // August 9, 2025 is a Saturday.
        let title = naming.makeTitle(for: event(date(2025, 8, 9, 10), date(2025, 8, 9, 18)))
        #expect(title.primary == "A Saturday in August")
    }

    @Test("Several days over a weekend")
    func weekend() {
        let title = naming.makeTitle(for: event(date(2025, 8, 9, 10), date(2025, 8, 10, 12)))
        #expect(title.primary == "August Weekend")
    }

    @Test("New Year's Eve is recognised")
    func newYearsEve() {
        let title = naming.makeTitle(for: event(date(2025, 12, 31, 21), date(2026, 1, 1, 0, 45)))
        #expect(title.primary == "New Year's Eve")
    }

    @Test("Moments inside a trip are named by day, or by place when it differs")
    func insideChapter() {
        let chapterPlace = PlaceName(name: "Kaş")
        let sameplace = MomentNamingContext(
            kind: .event, start: date(2025, 8, 8, 18), end: date(2025, 8, 8, 20),
            place: PlaceName(name: "Kaş"), chapterPlace: chapterPlace, isInChapter: true, assetCount: 5
        )
        #expect(naming.makeTitle(for: sameplace) == MomentTitle(primary: "Friday Evening", secondary: "August 8"))

        let elsewhere = MomentNamingContext(
            kind: .event, start: date(2025, 8, 8, 10), end: date(2025, 8, 8, 12),
            place: PlaceName(name: "Kekova"), chapterPlace: chapterPlace, isInChapter: true, assetCount: 5
        )
        #expect(naming.makeTitle(for: elsewhere).primary == "Kekova")
    }

    @Test("Collections and undated moments")
    func collectionAndUndated() {
        let collection = MomentNamingContext(kind: .collection, start: date(2024, 3, 2), end: date(2024, 3, 28), place: nil, assetCount: 4)
        #expect(naming.makeTitle(for: collection) == MomentTitle(primary: "Moments from March", secondary: "2024"))
        let undated = MomentNamingContext(kind: .undated, start: nil, end: nil, place: nil, assetCount: 3)
        #expect(naming.makeTitle(for: undated).primary == "Without a date")
    }

    @Test("Chapters are named after their place and months")
    func chapters() {
        let single = naming.makeChapterTitle(for: ChapterNamingContext(
            start: date(2025, 8, 6), end: date(2025, 8, 9), place: PlaceName(name: "Kaş"), momentCount: 4
        ))
        #expect(single == MomentTitle(primary: "Kaş", secondary: "August 2025"))
        let spanning = naming.makeChapterTitle(for: ChapterNamingContext(
            start: date(2025, 7, 29), end: date(2025, 8, 3), place: nil, momentCount: 3
        ))
        #expect(spanning == MomentTitle(primary: "A Few Days Away", secondary: "July – August 2025"))
    }

    @Test("Names never contain emotional claims")
    func factualOnly() {
        let banned = ["happ", "love", "best", "magic", "perfect", "romantic", "special"]
        let contexts = [
            event(date(2025, 8, 6, 18), date(2025, 8, 6, 21), place: "Kaş"),
            event(date(2024, 12, 12, 19), date(2024, 12, 12, 21)),
            event(date(2025, 8, 9, 10), date(2025, 8, 10, 12)),
            event(date(2025, 2, 14, 19), date(2025, 2, 14, 22)),
        ]
        for context in contexts {
            let text = naming.makeTitle(for: context).combined.lowercased()
            #expect(!banned.contains { text.contains($0) }, "\(text)")
        }
    }
}
