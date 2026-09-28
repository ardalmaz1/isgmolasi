import Foundation
import Testing
@testable import ReliveCore

@Suite("MomentClusterer")
struct MomentClustererTests {
    let clusterer = MomentClusterer(calendar: testCalendar)

    @Test("An evening of photos minutes apart is one moment")
    func eveningStaysTogether() {
        // 18:32, 18:46, 18:48, 19:02, 19:17 — the example from the product spec.
        let assets = burst(from: date(2025, 8, 6, 18, 32), minutes: [0, 14, 16, 30, 45], prefix: "evening")
        let clusters = clusterer.cluster(assets)
        #expect(clusters.count == 1)
        #expect(clusters[0].count == 5)
    }

    @Test("Monday evening and Thursday morning are different moments")
    func differentDaysSplit() {
        let monday = makeAsset("monday", at: date(2025, 8, 4, 18, 32))
        let thursday = makeAsset("thursday", at: date(2025, 8, 7, 11, 0))
        let clusters = clusterer.cluster([thursday, monday])
        #expect(clusters.map { $0.map(\.id) } == [["monday"], ["thursday"]])
    }

    @Test("Photos after midnight belong to the evening before")
    func lateNightJoinsEvening() {
        let assets = [
            makeAsset("dinner", at: date(2025, 12, 31, 22, 40)),
            makeAsset("toast", at: date(2025, 12, 31, 23, 55)),
            makeAsset("afterparty", at: date(2026, 1, 1, 0, 50)),
        ]
        #expect(clusterer.cluster(assets).count == 1)
    }

    @Test("Sleeping splits even a modest gap")
    func overnightSplits() {
        let assets = [
            makeAsset("night", at: date(2025, 6, 14, 23, 30)),
            makeAsset("morning", at: date(2025, 6, 15, 9, 0)),
        ]
        let decision = clusterer.decide(
            previous: assets[0], next: assets[1], lastKnownLocation: nil, gapIndex: 0, gaps: [9.5 * 3600]
        )
        #expect(decision == .splitOvernight)
        #expect(clusterer.cluster(assets).count == 2)
    }

    @Test("A sparse day of photos stays one moment")
    func sparseDayMerges() {
        // Someone who takes one photo every 2.5 hours: that's their normal rhythm.
        let assets = burst(from: date(2025, 5, 10, 10, 0), minutes: [0, 150, 300, 450], prefix: "sparse")
        #expect(clusterer.cluster(assets).count == 1)
    }

    @Test("A long pause inside dense shooting splits")
    func densePauseSplits() {
        let dinner = burst(from: date(2025, 5, 10, 18, 0), minutes: Array(stride(from: 0.0, to: 40, by: 2)), prefix: "dinner")
        let later = burst(from: date(2025, 5, 10, 21, 0), minutes: [0, 1, 2, 3], prefix: "later")
        let clusters = clusterer.cluster(dinner + later)
        #expect(clusters.count == 2)
        #expect(clusters[0].count == dinner.count)
    }

    @Test("Staying at the same place keeps a long afternoon together")
    func samePlaceMerges() {
        let beach = burst(from: date(2025, 8, 7, 11, 0), minutes: Array(stride(from: 0.0, to: 20, by: 1)), location: Places.kas, prefix: "beach")
        let sunset = burst(from: date(2025, 8, 7, 16, 30), minutes: [0, 1, 2], location: Places.kasHarbour, prefix: "sunset")
        #expect(clusterer.cluster(beach + sunset).count == 1)
    }

    @Test("Moving somewhere far away starts a new moment")
    func differentPlaceSplits() {
        let morning = burst(from: date(2025, 8, 8, 9, 0), minutes: [0, 5, 10], location: Places.kas, prefix: "kas")
        let boat = burst(from: date(2025, 8, 8, 10, 0), minutes: [0, 5, 10], location: Places.ankara, prefix: "far")
        #expect(clusterer.cluster(morning + boat).count == 2)
    }

    @Test("Undated assets are ignored by the clusterer")
    func undatedIgnored() {
        let assets = [makeAsset("undated", at: nil), makeAsset("dated", at: date(2025, 1, 1))]
        #expect(clusterer.cluster(assets).flatMap { $0 }.map(\.id) == ["dated"])
    }

    @Test("Adaptive threshold is clamped to its bounds")
    func thresholdClamped() {
        let config = ClusteringConfiguration.standard
        let dense = clusterer.adaptiveThreshold(gapIndex: 2, gaps: [60, 60, 7200, 60, 60])
        #expect(dense == config.minimumSplitGap)
        let sparse = clusterer.adaptiveThreshold(gapIndex: 1, gaps: [36_000, 7200, 36_000])
        #expect(sparse == config.maximumSplitGap)
    }
}
