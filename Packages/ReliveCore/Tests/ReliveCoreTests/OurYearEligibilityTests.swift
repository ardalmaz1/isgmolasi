import Foundation
import Testing
@testable import ReliveCore

/// Our Year must actually represent a year: one month is not a year.
@Suite("Our Year eligibility")
struct OurYearEligibilityTests {
    /// A story of `months` (month → number of evenings, 3 photos each) in 2026.
    private func library(_ months: [Int: Int]) -> CreationLibrary {
        var assets: [MemoryAsset] = []
        var moments: [Moment] = []
        for (month, evenings) in months.sorted(by: { $0.key < $1.key }) {
            for evening in 0..<evenings {
                let members = (0..<3).map { makeAsset("m\(month)-e\(evening)-\($0)", at: date(2026, month, 1 + evening * 2, 19, $0 * 10)) }
                assets += members
                moments.append(Moment(
                    id: UUID(), kind: .event, assetIDs: members.map(\.id), featuredAssetIDs: members.map(\.id),
                    startDate: members.first?.creationDate, endDate: members.last?.creationDate,
                    title: MomentTitle(primary: "Evening")
                ))
            }
        }
        return CreationLibrary(
            story: Story(generatedAt: date(2026, 10, 4), moments: moments, chapters: []),
            assets: Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) }),
            userStates: [:], unavailableAssetIDs: [], calendar: testCalendar
        )
    }

    @Test("Only September memories are not a year, however many there are")
    func septemberOnly() {
        let review = YearInReviewBuilder(library: library([9: 10])).review(for: 2026)
        #expect(review.statistics.memoryCount == 30)
        #expect(review.eligibility == .singleMonth(MonthKey(year: 2026, month: 9)))
        #expect(!review.isSufficient)
    }

    @Test("Several months with enough memories are a year")
    func severalMonths() {
        let review = YearInReviewBuilder(library: library([1: 1, 3: 1, 9: 1])).review(for: 2026)
        #expect(review.eligibility == .eligible)
        #expect(review.months.map(\.month.month) == [1, 3, 9], "chronological; empty months aren't listed")
    }

    @Test("Two months with only a few memories are not a year yet")
    func tooFew() {
        let review = YearInReviewBuilder(library: library([2: 1, 5: 1])).review(for: 2026)
        #expect(review.statistics.memoryCount == 6)
        #expect(review.eligibility == .tooFew(memories: 6))
    }

    @Test("A year with nothing in it")
    func empty() {
        #expect(YearInReviewBuilder(library: library([9: 2])).review(for: 2024).eligibility == .empty)
    }

    @Test("The fixture's 2025 (August and September) is a year; its 2026 (one April morning) is not")
    func fixtureYears() {
        let library = CreationFixture.make().library
        #expect(YearInReviewBuilder(library: library).review(for: 2025).isSufficient)
        #expect(YearInReviewBuilder(library: library).review(for: 2026).eligibility == .singleMonth(MonthKey(year: 2026, month: 4)))
    }

    @Test("A story of a one-month year doesn't close with \"that's our year\"")
    func noYearClosing() throws {
        let story = try StorySequenceBuilder(library: library([9: 3])).sequence(for: .year(2026)).get()
        #expect(!story.cards.contains { $0.kind == .closing && $0.title == .year(2026) })
        #expect(story.facts.title == .month(MonthKey(year: 2026, month: 9)), "it is September, not 'Our 2026'")
        let full = try StorySequenceBuilder(library: library([1: 1, 3: 1, 9: 1])).sequence(for: .year(2026)).get()
        #expect(full.cards.last?.kind == .closing && full.cards.last?.title == .year(2026))
    }
}
