import Foundation
import Testing
@testable import ReliveCore

/// Correctness of capture dates and places from import to every surface. The fixture is the
/// acceptance library: six months of two years, several photos each, plus midnight and
/// unknown-metadata cases. Calendar is UTC+3 (`testCalendar`), so a careless UTC conversion
/// would move the midnight photos into the wrong month and year.
enum IntegrityFixture {
    /// (prefix, year, month, day, count) — 44 photos.
    static let months: [(String, Int, Int, Int, Int)] = [
        ("apr25", 2025, 4, 12, 8),
        ("may25", 2025, 5, 3, 5),
        ("sep25", 2025, 9, 10, 12),
        ("jan26", 2026, 1, 5, 6),
        ("sep26", 2026, 9, 18, 9),
        ("oct26", 2026, 10, 4, 4),
    ]
    static let now = date(2026, 10, 5, 12)

    static func assets() -> [MemoryAsset] {
        months.flatMap { prefix, year, month, day, count in
            (0..<count).map { index in
                makeAsset("\(prefix)-\(index)", at: date(year, month, day, 14, index * 7), location: index.isMultiple(of: 2) ? Places.kas : nil)
            }
        }
    }

    static func build(_ assets: [MemoryAsset]) async throws -> (CreationLibrary, MemoryEngineResult) {
        let result = try await makeEngine().buildStory(from: assets, now: now)
        let library = CreationLibrary(
            story: result.story,
            assets: Dictionary(uniqueKeysWithValues: result.assets.map { ($0.id, $0) }),
            userStates: [:],
            unavailableAssetIDs: [],
            calendar: testCalendar
        )
        return (library, result)
    }

    static func ids(_ prefix: String, _ count: Int) -> [AssetID] {
        (0..<count).map { "\(prefix)-\($0)" }
    }
}

@Suite("Data integrity: capture dates")
struct DataIntegrityTests {
    // A, L, M
    @Test func importKeepsExactSourceDatesAndUnknownsStayUnknown() async throws {
        var assets = IntegrityFixture.assets()
        assets.append(makeAsset("undated-0", at: nil))
        assets.append(makeAsset("undated-1", at: nil, location: Places.kadikoy))
        let (library, result) = try await IntegrityFixture.build(assets)
        let output = Dictionary(uniqueKeysWithValues: result.assets.map { ($0.id, $0) })
        for input in assets {
            #expect(output[input.id]?.creationDate == input.creationDate, "\(input.id) keeps its exact capture date")
            #expect(output[input.id]?.location == input.location, "\(input.id) keeps its location, or none")
        }
        // Unknown stays unknown: no month, no year, no invented date anywhere.
        let index = TemporalIndex(library: library)
        #expect(index.undatedCount == 2)
        #expect(!index.entries.contains { $0.assetID.hasPrefix("undated") })
        #expect(output["undated-0"]?.creationDate == nil)
        #expect(output["undated-0"]?.location == nil)
        let undatedMoment = try #require(result.story.moments.first { $0.kind == .undated })
        #expect(undatedMoment.startDate == nil && undatedMoment.endDate == nil)
    }

    // D
    @Test func monthGroupingIsExact() async throws {
        let (library, _) = try await IntegrityFixture.build(IntegrityFixture.assets())
        let index = TemporalIndex(library: library)
        #expect(index.entries.count == 44)
        #expect(index.months == [
            MonthKey(year: 2026, month: 10), MonthKey(year: 2026, month: 9), MonthKey(year: 2026, month: 1),
            MonthKey(year: 2025, month: 9), MonthKey(year: 2025, month: 5), MonthKey(year: 2025, month: 4),
        ])
        #expect(index.countsByMonth == [
            MonthKey(year: 2025, month: 4): 8, MonthKey(year: 2025, month: 5): 5, MonthKey(year: 2025, month: 9): 12,
            MonthKey(year: 2026, month: 1): 6, MonthKey(year: 2026, month: 9): 9, MonthKey(year: 2026, month: 10): 4,
        ])
        #expect(MonthlyRecapBuilder(library: library).availableMonths() == index.months)
    }

    // E, H, I
    @Test func yearGroupingAndFirstMemoryAreExact() async throws {
        let (library, _) = try await IntegrityFixture.build(IntegrityFixture.assets())
        let builder = YearInReviewBuilder(library: library)
        #expect(builder.availableYears() == [2026, 2025])

        let year2025 = builder.review(for: 2025)
        #expect(year2025.statistics.memoryCount == 25)
        #expect(year2025.months.map(\.month) == [MonthKey(year: 2025, month: 4), MonthKey(year: 2025, month: 5), MonthKey(year: 2025, month: 9)])
        #expect(year2025.months.map(\.memoryCount) == [8, 5, 12])
        #expect(year2025.firstMemory?.assetID == "apr25-0")
        #expect(year2025.firstMemory?.date == date(2025, 4, 12, 14, 0))
        let photos2025 = year2025.moments.flatMap(\.assetIDs)
        #expect(photos2025.allSatisfy { testCalendar.component(.year, from: library.assets[$0]!.creationDate!) == 2025 })

        let year2026 = builder.review(for: 2026)
        #expect(year2026.statistics.memoryCount == 19)
        #expect(year2026.months.map(\.memoryCount) == [6, 9, 4])
        #expect(year2026.firstMemory?.assetID == "jan26-0")
        #expect(year2026.firstMoment?.startDate == date(2026, 1, 5, 14, 0))
        // No 2025 photo is ever counted in 2026.
        #expect(!year2026.moments.flatMap(\.assetIDs).contains { $0.hasSuffix("25") || $0.contains("25-") })
    }

    // G
    @Test func aMonthlyRecapHoldsOnlyItsMonth() async throws {
        let (library, _) = try await IntegrityFixture.build(IntegrityFixture.assets())
        let builder = MonthlyRecapBuilder(library: library)
        for (prefix, year, month, _, count) in IntegrityFixture.months {
            let key = MonthKey(year: year, month: month)
            let recap = builder.recap(for: key)
            #expect(recap.statistics.memoryCount == count, "\(prefix) count")
            let shown = Set(recap.moments.flatMap(\.assetIDs))
            #expect(shown == Set(IntegrityFixture.ids(prefix, count)), "\(prefix) holds exactly its own photos")
            #expect(recap.highlights(limit: 50).allSatisfy { MonthKey(date: library.assets[$0]!.creationDate!, calendar: testCalendar) == key })
            if let span = recap.dateSpan {
                #expect(MonthKey(date: span.start, calendar: testCalendar) == key && MonthKey(date: span.end, calendar: testCalendar) == key)
            }
        }
        // September 2026 never contains a 2025 photo.
        let september2026 = builder.recap(for: MonthKey(year: 2026, month: 9))
        #expect(september2026.moments.flatMap(\.assetIDs).allSatisfy { $0.hasPrefix("sep26") })
    }

    // F
    @Test func distantMonthsNeverBecomeOneMoment() async throws {
        // Same place, nothing else between them: still separate moments, each within its day.
        let assets = IntegrityFixture.assets().map { asset -> MemoryAsset in
            var copy = asset
            copy.location = Places.kas
            return copy
        }
        let (_, result) = try await IntegrityFixture.build(assets)
        #expect(result.story.moments.count == IntegrityFixture.months.count)
        for moment in result.story.moments {
            let months = Set(moment.assetIDs.compactMap { id in assets.first { $0.id == id }?.creationDate }.map { MonthKey(date: $0, calendar: testCalendar) })
            #expect(months.count == 1, "\(moment.title.primary) stays within one month")
            #expect(Set(moment.assetIDs.map { $0.split(separator: "-")[0] }).count == 1, "one source day per moment")
        }
    }

    // P
    @Test func photosAfterMidnightBelongToTheirOwnMonthAndYear() async throws {
        let assets = [
            makeAsset("nye-0", at: date(2024, 12, 31, 23, 30)),
            makeAsset("nye-1", at: date(2024, 12, 31, 23, 50)),
            makeAsset("nye-2", at: date(2025, 1, 1, 0, 15)),
            makeAsset("nye-3", at: date(2025, 1, 1, 0, 40)),
            // The last evening of a month: 23:59 stays in that month.
            makeAsset("eom-0", at: date(2025, 3, 31, 23, 59)),
            makeAsset("eom-1", at: date(2025, 4, 1, 0, 1)),
        ]
        let (library, result) = try await IntegrityFixture.build(assets)
        // One New Year's Eve moment (people stay up past midnight)…
        let eve = try #require(result.story.moments.first { $0.assetIDs.contains("nye-0") })
        #expect(eve.assetIDs.contains("nye-3"))
        // …but every photo is counted in the month and year it was taken.
        let index = TemporalIndex(library: library)
        #expect(index.countsByMonth[MonthKey(year: 2024, month: 12)] == 2)
        #expect(index.countsByMonth[MonthKey(year: 2025, month: 1)] == 2)
        #expect(index.countsByMonth[MonthKey(year: 2025, month: 3)] == 1)
        #expect(index.countsByMonth[MonthKey(year: 2025, month: 4)] == 1)
        let years = YearInReviewBuilder(library: library)
        #expect(years.review(for: 2024).statistics.memoryCount == 2)
        #expect(years.review(for: 2025).firstMemory?.assetID == "nye-2")
        let january = MonthlyRecapBuilder(library: library).recap(for: MonthKey(year: 2025, month: 1))
        #expect(Set(january.moments.flatMap(\.assetIDs)) == ["nye-2", "nye-3"])
        #expect(january.moments.first?.startDate == date(2025, 1, 1, 0, 15), "dated by its own photos")
    }

    // Q
    @Test func orderIsChronologicalAndDeterministic() async throws {
        var assets = IntegrityFixture.assets()
        assets.append(makeAsset("tie-b", at: date(2025, 5, 3, 14, 0)))
        assets.append(makeAsset("tie-a", at: date(2025, 5, 3, 14, 0)))
        let (first, _) = try await IntegrityFixture.build(assets.shuffled())
        let (second, _) = try await IntegrityFixture.build(assets.reversed())
        let a = TemporalIndex(library: first).entries
        let b = TemporalIndex(library: second).entries
        #expect(a.map(\.assetID) == b.map(\.assetID))
        #expect(zip(a, a.dropFirst()).allSatisfy { $0.date < $1.date || ($0.date == $1.date && $0.assetID < $1.assetID) })
    }

    // Hidden moments don't count, duplicate copies are never placed in a month.
    @Test func hiddenMomentsAndDuplicateCopiesStayOutOfTheCalendar() async throws {
        let (library, result) = try await IntegrityFixture.build(IntegrityFixture.assets())
        let april = try #require(result.story.moments.first { $0.assetIDs.contains("apr25-0") })
        var hidden = library
        hidden.userStates[april.id] = MomentUserState(isHidden: true)
        #expect(TemporalIndex(library: hidden).countsByMonth[MonthKey(year: 2025, month: 4)] == nil)

        // A copy saved in September 2026 of an April 2025 photo lives with its original moment
        // but is never counted in September 2026 (or anywhere): it's the same memory.
        var withCopy = library
        var moment = try #require(withCopy.story.moments.firstIndex { $0.id == april.id }.map { withCopy.story.moments[$0] })
        withCopy.assets["copy-0"] = makeAsset("copy-0", at: date(2026, 9, 18, 20))
        moment.assetIDs.append("copy-0")
        moment.similarAssetIDs.append("copy-0")
        moment.duplicateAssetIDs.append("copy-0")
        if let position = withCopy.story.moments.firstIndex(where: { $0.id == april.id }) {
            withCopy.story.moments[position] = moment
        }
        let index = TemporalIndex(library: withCopy)
        #expect(!index.entries.contains { $0.assetID == "copy-0" })
        #expect(index.countsByMonth[MonthKey(year: 2026, month: 9)] == 9)
    }
}

@Suite("Data integrity: creations from mixed periods")
struct MixedPeriodCreationTests {
    static let mixed = IntegrityFixture.ids("apr25", 4) + IntegrityFixture.ids("sep26", 4)

    /// A month or year title for photos that span more than that would be a false claim.
    static func claimsOnePeriod(_ title: CreationTitle?) -> Bool {
        switch title {
        case .month, .year: true
        case .named, nil: false
        }
    }

    // K
    @Test func storyFromAprilAndSeptemberDoesNotClaimSeptember() async throws {
        let (library, _) = try await IntegrityFixture.build(IntegrityFixture.assets())
        let design = try StoryDesigner(library: library).makeItForMe(source: .photos(Self.mixed), variation: 0).get()
        #expect(!Self.claimsOnePeriod(design.facts.title), "no month or year covers both: \(String(describing: design.facts.title))")
        let span = try #require(design.facts.dateSpan)
        #expect(span.start == date(2025, 4, 12, 14, 0))
        #expect(testCalendar.component(.year, from: span.end) == 2026)
        let opening = try #require(design.cards.first)
        #expect(!Self.claimsOnePeriod(opening.title), "the opening card claims one period: \(String(describing: opening.title))")
    }

    // J
    @Test func bookFromAprilAndSeptemberDoesNotClaimSeptember() async throws {
        let (library, _) = try await IntegrityFixture.build(IntegrityFixture.assets())
        let book = try MemoryBookBuilder(library: library).makeBook(from: .photos(Self.mixed), now: IntegrityFixture.now).get()
        let layout = BookLayoutEngine(library: library).layout(book)
        #expect(!Self.claimsOnePeriod(layout.facts.title), "\(String(describing: layout.facts.title))")
        let span = try #require(layout.facts.dateSpan)
        #expect(testCalendar.component(.year, from: span.start) == 2025 && testCalendar.component(.year, from: span.end) == 2026)
        // Page dates come from the photos on that page.
        for page in layout.pages where page.kind == .photos {
            guard let running = page.runningDate else { continue }
            let dates = page.photoIDs.compactMap { library.assets[$0]?.creationDate }
            #expect(running == DateSpan(dates: dates), "page \(page.id) is dated by its own photos")
        }
    }

    @Test func collageAndStoryFromOneMonthUseOnlyThatMonth() async throws {
        let (library, _) = try await IntegrityFixture.build(IntegrityFixture.assets())
        let september = CreationSource.month(MonthKey(year: 2026, month: 9))
        let photos = library.availablePhotos(for: september)
        #expect(Set(photos) == Set(IntegrityFixture.ids("sep26", 9)))
        #expect(library.initialPhotos(for: september, limit: 6).allSatisfy { $0.hasPrefix("sep26") })
        let design = try StoryDesigner(library: library).makeItForMe(source: september, variation: 0).get()
        #expect(design.photoIDs.allSatisfy { $0.hasPrefix("sep26") })
        #expect(design.facts.title == .month(MonthKey(year: 2026, month: 9)), "a September 2026 story may say September")
        let year = CreationSource.year(2025)
        #expect(library.availablePhotos(for: year).allSatisfy { $0.contains("25-") })
        #expect(library.availablePhotos(for: year).count == 25)
    }
}

@Suite("Data integrity: metadata repair")
struct MetadataRepairTests {
    static let now = IntegrityFixture.now

    // N, O
    @Test func repairRestoresLibraryDatesWithoutDuplicatesAndIsIdempotent() {
        let library = IntegrityFixture.assets()
        // What an earlier run stored: some dates moved to September 2026, analysis cached.
        var stored = Dictionary(uniqueKeysWithValues: library.map { ($0.id, $0) })
        for id in IntegrityFixture.ids("apr25", 8) {
            stored[id]?.creationDate = date(2026, 9, 10, 20)
            stored[id]?.analysis = AssetAnalysis(sharpness: 0.9, aestheticScore: 0.8)
        }
        let first = MetadataRepair().repair(stored: stored, library: library, now: Self.now)
        #expect(first.changes.count == 8)
        #expect(first.changes.allSatisfy { $0.dateChanged && !$0.locationChanged })
        #expect(first.needsRebuild)
        #expect(first.assets.count == stored.count, "nothing added or removed")
        #expect(first.assets["apr25-0"]?.creationDate == date(2025, 4, 12, 14, 0))
        #expect(first.assets["apr25-0"]?.analysis?.sharpness == 0.9, "cached analysis kept")

        let second = MetadataRepair().repair(stored: first.assets, library: library, now: Self.now)
        #expect(second.changes.isEmpty, "running it again changes nothing")
        #expect(!second.needsRebuild)
        #expect(second.assets == first.assets)
    }

    @Test func repairLeavesMissingMemoriesAndNeverInventsDates() {
        let stored: [AssetID: MemoryAsset] = [
            "kept": makeAsset("kept", at: date(2025, 4, 12)),
            "deleted": makeAsset("deleted", at: date(2025, 5, 3)),
            "undated": makeAsset("undated", at: nil),
        ]
        let library = [
            makeAsset("kept", at: date(2025, 4, 12)),
            makeAsset("undated", at: nil),
            makeAsset("not-stored", at: date(2026, 1, 1)),
        ]
        let result = MetadataRepair().repair(stored: stored, library: library, now: Self.now)
        #expect(result.changes.isEmpty)
        #expect(result.notInLibrary == ["deleted"])
        #expect(Set(result.assets.keys) == ["kept", "deleted", "undated"], "never adds what the user didn't choose")
        #expect(result.assets["undated"]?.creationDate == nil, "unknown stays unknown")
        #expect(result.assets["deleted"]?.creationDate == date(2025, 5, 3), "left as stored")
    }

    @Test func aFutureCaptureDateBecomesUnknownNotNow() {
        let stored: [AssetID: MemoryAsset] = ["clock": makeAsset("clock", at: date(2025, 4, 12))]
        let library = [makeAsset("clock", at: date(2031, 1, 1))]
        let result = MetadataRepair().repair(stored: stored, library: library, now: Self.now)
        #expect(result.assets["clock"]?.creationDate == nil)
        #expect(result.changes.first?.dateChanged == true)
    }

    // O: after a repair, the rebuilt story keeps moment identities, so notes, hidden state and
    // favorites stay attached.
    @Test func rebuildAfterRepairKeepsMomentIdentities() async throws {
        let library = IntegrityFixture.assets()
        let (_, before) = try await IntegrityFixture.build(library)
        // Another photo's date was corrected in Photos: from 14:00 to 14:30 the same day.
        var corrected = library
        if let index = corrected.firstIndex(where: { $0.id == "sep25-3" }) {
            corrected[index].creationDate = date(2025, 9, 10, 14, 30)
        }
        let repair = MetadataRepair().repair(stored: Dictionary(uniqueKeysWithValues: before.assets.map { ($0.id, $0) }), library: corrected, now: Self.now)
        #expect(repair.changes.map(\.assetID) == ["sep25-3"])
        let (_, after) = try await IntegrityFixture.build(Array(repair.assets.values))
        let reconciled = MomentReconciler().reconcile(new: after.story, previous: before.story)
        #expect(Set(reconciled.moments.map(\.id)) == Set(before.story.moments.map(\.id)))
    }

    @Test func auditCountsWithoutIdentifiers() {
        var assets = IntegrityFixture.assets()
        assets.append(makeAsset("undated", at: nil))
        let audit = MetadataAudit(assets: assets, calendar: testCalendar)
        #expect(audit.assets == 45 && audit.validDates == 44 && audit.unknownDates == 1)
        #expect(audit.years.map(\.count) == [25, 19])
        let line = audit.logLine(repaired: 3)
        #expect(line == "metadata_audit assets=45 validDates=44 unknownDates=1 located=23 years=[2025:25,2026:19] months=[2025-04:8,2025-05:5,2025-09:12,2026-01:6,2026-09:9,2026-10:4] repaired=3")
        #expect(!line.contains("apr25"))
    }
}
