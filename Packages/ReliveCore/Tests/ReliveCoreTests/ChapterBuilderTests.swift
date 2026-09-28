import Foundation
import Testing
@testable import ReliveCore

@Suite("ChapterBuilder")
struct ChapterBuilderTests {
    let builder = ChapterBuilder(calendar: testCalendar)

    /// Everyday life at home across several months, so "home" can be recognised.
    func homeLife() -> [ClusterSummary] {
        (1...6).map { month in
            ClusterSummary(start: date(2025, month, 10, 19), end: date(2025, month, 10, 21), centroid: Places.kadikoy)
        }
    }

    @Test("A Kaş trip with a day in Kekova becomes one chapter")
    func tripBecomesChapter() {
        let trip = [
            ClusterSummary(start: date(2025, 8, 6, 17), end: date(2025, 8, 6, 22), centroid: Places.kas),
            ClusterSummary(start: date(2025, 8, 7, 10), end: date(2025, 8, 7, 19), centroid: Places.kas),
            ClusterSummary(start: date(2025, 8, 8, 9), end: date(2025, 8, 8, 16), centroid: Places.kekova),
            ClusterSummary(start: date(2025, 8, 9, 10), end: date(2025, 8, 9, 13), centroid: Places.kasHarbour),
        ]
        let clusters = homeLife() + trip + [
            ClusterSummary(start: date(2025, 8, 20, 19), end: date(2025, 8, 20, 21), centroid: Places.kadikoy),
        ]
        let runs = builder.chapterRuns(for: clusters)
        #expect(runs == [[6, 7, 8, 9]])
    }

    @Test("Home flags mark everyday places, not trips")
    func homeFlags() {
        let clusters = homeLife() + [
            ClusterSummary(start: date(2025, 8, 6, 17), end: date(2025, 8, 6, 22), centroid: Places.kas),
            ClusterSummary(start: date(2025, 8, 7, 10), end: date(2025, 8, 7, 12), centroid: nil),
        ]
        #expect(builder.homeFlags(for: clusters) == [true, true, true, true, true, true, false, false])
    }

    @Test("Consecutive days at home are not a trip")
    func homeIsNotATrip() {
        var clusters = homeLife()
        clusters.append(ClusterSummary(start: date(2025, 7, 1, 19), end: date(2025, 7, 1, 21), centroid: Places.moda))
        clusters.append(ClusterSummary(start: date(2025, 7, 2, 19), end: date(2025, 7, 2, 21), centroid: Places.kadikoy))
        #expect(builder.chapterRuns(for: clusters).isEmpty)
    }

    @Test("Unlocated moments inside a trip join it; trailing ones don't")
    func unlocatedSandwich() {
        let clusters = homeLife() + [
            ClusterSummary(start: date(2025, 8, 6, 17), end: date(2025, 8, 6, 22), centroid: Places.kas),
            ClusterSummary(start: date(2025, 8, 7, 10), end: date(2025, 8, 7, 12), centroid: nil),
            ClusterSummary(start: date(2025, 8, 8, 10), end: date(2025, 8, 8, 12), centroid: Places.kas),
            ClusterSummary(start: date(2025, 8, 9, 10), end: date(2025, 8, 9, 12), centroid: nil),
        ]
        #expect(builder.chapterRuns(for: clusters) == [[6, 7, 8]])
    }

    @Test("A long break ends the trip")
    func gapBreaksTrip() {
        let clusters = homeLife() + [
            ClusterSummary(start: date(2025, 8, 6, 17), end: date(2025, 8, 6, 22), centroid: Places.kas),
            ClusterSummary(start: date(2025, 8, 12, 10), end: date(2025, 8, 12, 12), centroid: Places.kas),
        ]
        #expect(builder.chapterRuns(for: clusters).isEmpty)
    }

    @Test("Same-day outings stay separate moments")
    func sameDayIsNotAChapter() {
        let clusters = homeLife() + [
            ClusterSummary(start: date(2025, 8, 6, 10), end: date(2025, 8, 6, 12), centroid: Places.kas),
            ClusterSummary(start: date(2025, 8, 6, 18), end: date(2025, 8, 6, 20), centroid: Places.kas),
        ]
        #expect(builder.chapterRuns(for: clusters).isEmpty)
    }

    @Test("No location data means no chapters")
    func noLocationNoChapters() {
        let clusters = (1...5).map { day in
            ClusterSummary(start: date(2025, 8, day, 10), end: date(2025, 8, day, 12), centroid: nil)
        }
        #expect(builder.chapterRuns(for: clusters).isEmpty)
    }
}
