import Foundation
import Testing
@testable import ReliveCore

/// Hand-built stories for the intelligence layer. Moments feature every photo (nothing
/// collapsed upstream), so the layer's own duplicate and similarity handling is what's tested.
struct IntelligenceFixture {
    struct Shot {
        var id: AssetID
        var date: Date?
        var location: GeoCoordinate? = nil
        var portrait = true
        var favorite = false
        var photosFavorite = false
        /// A look: shots with the same look (and close in time) are near-identical.
        var look: [Float]
        var faces = 0
        var quality = 0.5
        var megapixelsScale = 1.0
    }

    struct MomentSpec {
        var key: String
        var title: String
        var shots: [Shot]
        var place: String? = nil
        var trip: String? = nil
        var hidden = false
        var duplicates: [AssetID] = []
        var userCover: AssetID? = nil
    }

    var moments: [MomentSpec]
    var unavailable: Set<AssetID> = []
    var favoriteIDs: Set<AssetID> { Set(moments.flatMap(\.shots).filter(\.favorite).map(\.id)) }

    static func momentID(_ key: String) -> MomentID { StableIdentifier.uuid(namespace: "intel", key: key) }
    static func tripID(_ key: String) -> UUID { StableIdentifier.uuid(namespace: "intel-trip", key: key) }

    /// A distinct look per index (one-hot, so different looks are far apart).
    static func look(_ index: Int) -> [Float] {
        var vector = [Float](repeating: 0, count: 64)
        vector[index % 64] = 1
        return vector
    }

    /// A look near `base` (inside the similar-shot distance).
    static func near(_ base: Int, drift: Float) -> [Float] {
        var vector = look(base)
        vector[(base + 1) % 64] = drift
        return vector
    }

    static func asset(_ shot: Shot) -> MemoryAsset {
        let width = Int(3024 * shot.megapixelsScale.squareRoot())
        let height = Int(4032 * shot.megapixelsScale.squareRoot())
        return makeAsset(
            shot.id,
            at: shot.date,
            location: shot.location,
            favorite: shot.photosFavorite,
            width: shot.portrait ? width : height,
            height: shot.portrait ? height : width,
            analysis: analysis(vector: shot.look, faces: shot.faces, faceQuality: shot.faces > 0 ? shot.quality : nil, sharpness: shot.quality, aesthetics: shot.quality)
        )
    }

    var library: CreationLibrary {
        var assets: [AssetID: MemoryAsset] = [:]
        var built: [Moment] = []
        var states: [MomentID: MomentUserState] = [:]
        var trips: [String: [Moment]] = [:]
        for spec in moments {
            for shot in spec.shots { assets[shot.id] = Self.asset(shot) }
            let dates = spec.shots.compactMap(\.date)
            let ids = spec.shots.map(\.id)
            let moment = Moment(
                id: Self.momentID(spec.key),
                kind: dates.isEmpty ? .undated : .event,
                assetIDs: ids,
                featuredAssetIDs: ids.filter { !spec.duplicates.contains($0) },
                similarAssetIDs: spec.duplicates,
                duplicateAssetIDs: spec.duplicates,
                heroAssetID: nil,
                startDate: dates.min(),
                endDate: dates.max(),
                place: spec.place.map { PlaceName(name: $0) },
                title: MomentTitle(primary: spec.title),
                chapterID: spec.trip.map(Self.tripID)
            )
            built.append(moment)
            if let trip = spec.trip { trips[trip, default: []].append(moment) }
            var state = MomentUserState()
            state.isHidden = spec.hidden
            state.heroOverrideAssetID = spec.userCover
            if !state.isDefault { states[moment.id] = state }
        }
        let chapters = trips.sorted { $0.key < $1.key }.map { key, members in
            Chapter(
                id: Self.tripID(key),
                momentIDs: members.map(\.id),
                startDate: members.compactMap(\.startDate).min() ?? .distantPast,
                endDate: members.compactMap(\.endDate).max() ?? .distantPast,
                place: members.first?.place,
                title: MomentTitle(primary: key)
            )
        }
        let story = Story(generatedAt: date(2026, 10, 13), moments: built.sorted { $0.sortDate < $1.sortDate }, chapters: chapters)
        var library = CreationLibrary(story: story, assets: assets, userStates: states, unavailableAssetIDs: unavailable, calendar: testCalendar)
        library.favoriteAssetIDs = favoriteIDs
        return library
    }

    var engine: MemoryIntelligenceEngine { MemoryIntelligenceEngine(library: library) }

    // MARK: Fixtures A–K

    /// A. Five photos, one afternoon, mixed shapes.
    static func smallMoment() -> IntelligenceFixture {
        let start = date(2026, 6, 8, 15)
        let shots = (0..<5).map { index in
            Shot(id: "small-\(index)", date: start.addingTimeInterval(Double(index) * 900), location: Places.kas,
                 portrait: index % 2 == 0, look: look(index), quality: 0.4 + Double(index) * 0.05)
        }
        return IntelligenceFixture(moments: [MomentSpec(key: "small", title: "Kaş", shots: shots, place: "Kaş")])
    }

    /// B. 15 near-identical selfies, two distinct landscapes, one favorite couple photo.
    static func burstHeavy() -> IntelligenceFixture {
        let start = date(2026, 7, 4, 18)
        var shots = (0..<15).map { index in
            Shot(id: "selfie-\(index)", date: start.addingTimeInterval(Double(index) * 10), look: near(0, drift: Float(index) * 0.01),
                 faces: 2, quality: 0.8 - Double(index) * 0.001)
        }
        shots.append(Shot(id: "landscape-0", date: start.addingTimeInterval(1_200), portrait: false, look: look(10), quality: 0.6))
        shots.append(Shot(id: "landscape-1", date: start.addingTimeInterval(1_500), portrait: false, look: look(11), quality: 0.55))
        shots.append(Shot(id: "couple", date: start.addingTimeInterval(1_800), favorite: true, look: look(20), faces: 2, quality: 0.5))
        return IntelligenceFixture(moments: [MomentSpec(key: "burst", title: "July Evening", shots: shots)])
    }

    /// C. A trip: 30 memories, 3 days, 2 places, both shapes.
    static func mixedTrip(year: Int = 2025) -> IntelligenceFixture {
        func day(_ key: String, _ title: String, _ dayOfMonth: Int, place: String, location: GeoCoordinate, offset: Int) -> MomentSpec {
            let start = date(year, 8, dayOfMonth, 10)
            var shots: [Shot] = []
            for index in 0..<10 {
                let when = start.addingTimeInterval(Double(index) * 1_800)
                let quality = 0.4 + Double((index * 7) % 5) / 10
                shots.append(Shot(id: "\(key)-\(index)", date: when, location: location,
                                  portrait: index % 3 != 0, look: look(offset + index), faces: index % 2, quality: quality))
            }
            return MomentSpec(key: key, title: title, shots: shots, place: place, trip: "Kaş & Kekova")
        }
        return IntelligenceFixture(moments: [
            day("d1", "Kaş", 6, place: "Kaş", location: Places.kas, offset: 0),
            day("d2", "Kaş Harbour", 7, place: "Kaş", location: Places.kasHarbour, offset: 10),
            day("d3", "Kekova", 8, place: "Kekova", location: Places.kekova, offset: 20),
        ])
    }

    /// D. April 2025, August 2025, January 2026, September 2026.
    static func mixedYears() -> IntelligenceFixture {
        let months: [(String, String, Int, Int)] = [("apr", "April Afternoon", 2025, 4), ("aug", "August Evening", 2025, 8), ("jan", "January Morning", 2026, 1), ("sep", "September Walk", 2026, 9)]
        return IntelligenceFixture(moments: months.enumerated().map { offset, entry in
            let (key, title, year, month) = entry
            let shots = (0..<3).map { index in
                Shot(id: "\(key)-\(index)", date: date(year, month, 10, 12).addingTimeInterval(Double(index) * 600), look: look(offset * 3 + index))
            }
            return MomentSpec(key: key, title: title, shots: shots)
        })
    }
}

// MARK: - Fixture tests

@Suite("Memory intelligence: selection")
struct MemoryIntelligenceSelectionTests {
    @Test func smallMomentKeepsItsPhotosInOrder() {
        let fixture = IntelligenceFixture.smallMoment()
        let plan = fixture.engine.plan(for: .moment(IntelligenceFixture.momentID("small")), target: .collage)
        #expect(plan.isReady)
        #expect(plan.selected == (0..<5).map { "small-\($0)" }, "five distinct photos, chronological")
        #expect(plan.period.kind == .day(DayKey(year: 2026, month: 6, day: 8)))
        #expect(plan.title.basis == .moment)
        #expect(plan.title.combined == "Kaş · June 8, 2026")
        #expect(plan.recommendations.first?.kind == .collage)
        #expect(plan.sequence.ordered.first == plan.lead)
    }

    @Test func burstHeavyMomentDoesNotBecomeASelfieWall() throws {
        let fixture = IntelligenceFixture.burstHeavy()
        let plan = fixture.engine.plan(for: .moment(IntelligenceFixture.momentID("burst")), target: .collage)
        let selfies = plan.selected.filter { $0.hasPrefix("selfie") }
        #expect(selfies.count == 1, "one selfie stands for the burst: \(plan.selected)")
        #expect(plan.selected.contains("landscape-0") && plan.selected.contains("landscape-1"))
        #expect(plan.selected.contains("couple"), "the favorite is always considered")
        #expect(plan.collapsedSimilar.count == 14)
        #expect(plan.similarityClusterCount == 1)

        // Even a book (room for everything) gets one selfie, not fifteen.
        let book = fixture.engine.plan(for: .moment(IntelligenceFixture.momentID("burst")), target: .general(limit: 40))
        #expect(book.selected.filter { $0.hasPrefix("selfie") }.count == 1)
    }

    @Test func aMixedTripCoversItsDaysPlacesAndShapes() {
        let fixture = IntelligenceFixture.mixedTrip()
        let tripID = IntelligenceFixture.tripID("Kaş & Kekova")
        let collage = fixture.engine.plan(for: .trip(tripID), target: .collage)
        #expect(collage.selected.count == 6)
        let moments = Set(collage.selected.compactMap { fixture.library.moment(containing: $0)?.id })
        #expect(moments.count == 3, "every day of the trip is represented")
        let shapes = Set(collage.selected.compactMap { fixture.library.creationAsset($0)?.orientation?.isLandscape })
        #expect(shapes == [true, false], "both portrait and landscape photos")

        let book = fixture.engine.plan(for: .trip(tripID), target: .book)
        #expect(book.selected.count == 30)
        #expect(book.title.basis == .trip)
        #expect(book.title.primary == "Kaş & Kekova")
        #expect(book.sequence.sections.count == 3)
        #expect(book.sequence.sections.map(\.transition).dropFirst().allSatisfy { $0 == .newDay })
        let kinds = book.recommendations.map(\.kind)
        #expect(kinds.contains(.book) && kinds.contains(.story) && kinds.contains(.movieFuture))
        #expect(book.recommendations.first { $0.kind == .movieFuture }?.isAvailable == false)
    }

    @Test func mixedYearsNeverClaimOneMonth() {
        let fixture = IntelligenceFixture.mixedYears()
        let ids = fixture.moments.flatMap(\.shots).map(\.id)
        let plan = fixture.engine.plan(IntelligenceRequest(pool: ids, target: .book))
        #expect(plan.period.kind == .years(first: 2025, last: 2026))
        #expect(plan.period.label(calendar: testCalendar) == "2025 – 2026")
        #expect(plan.title.primary == "Our Memories")
        #expect(plan.title.combined == "Our Memories · 2025 – 2026")
        for month in ["January", "April", "August", "September"] {
            #expect(!plan.title.combined.contains(month))
        }
        #expect(!plan.recommendations.contains { $0.kind == .monthlyRecap || $0.kind == .yearInReview })
        #expect(plan.sequence.sections.map(\.transition) == [.start, .newMonth, .newYear, .newMonth])
    }

    @Test func aFavoriteIsPreferredButNeverDuplicated() {
        let start = date(2026, 5, 1, 12)
        let shots = [
            IntelligenceFixture.Shot(id: "sharp", date: start, look: IntelligenceFixture.near(0, drift: 0), quality: 0.7),
            IntelligenceFixture.Shot(id: "favorite", date: start.addingTimeInterval(20), favorite: true, look: IntelligenceFixture.near(0, drift: 0.05), quality: 0.65),
            IntelligenceFixture.Shot(id: "other", date: start.addingTimeInterval(3_000), look: IntelligenceFixture.look(5), quality: 0.5),
        ]
        let fixture = IntelligenceFixture(moments: [.init(key: "fav", title: "May Afternoon", shots: shots)])
        let plan = fixture.engine.plan(for: .moment(IntelligenceFixture.momentID("fav")), target: .collage)
        #expect(plan.selected.contains("favorite"))
        #expect(!plan.selected.contains("sharp"), "the near-identical shot is folded into the favorite")
        #expect(plan.collapsedSimilar["sharp"] == "favorite")
        #expect(plan.lead == "favorite")
        #expect(plan.leadReason == .favorite)
    }

    @Test func missingDatesAndPlacesStayUnknown() {
        let shots = [
            IntelligenceFixture.Shot(id: "undated-0", date: nil, look: IntelligenceFixture.look(1)),
            IntelligenceFixture.Shot(id: "undated-1", date: nil, look: IntelligenceFixture.look(2)),
            IntelligenceFixture.Shot(id: "dated", date: date(2026, 2, 14, 19), look: IntelligenceFixture.look(3)),
        ]
        let fixture = IntelligenceFixture(moments: [
            .init(key: "undated", title: "", shots: Array(shots.prefix(2))),
            .init(key: "dated", title: "February Evening", shots: [shots[2]]),
        ])
        let plan = fixture.engine.plan(IntelligenceRequest(pool: shots.map(\.id), target: .story))
        let candidates = MemoryCandidate.build(shots.map(\.id), library: fixture.library)
        #expect(candidates.filter { $0.captureDate == nil }.map(\.assetID).sorted() == ["undated-0", "undated-1"], "no borrowed dates")
        #expect(candidates.allSatisfy { $0.place == nil && !$0.hasLocation }, "no borrowed places")
        #expect(!plan.period.isComplete)
        #expect(plan.title.primary == "Our Memories" && plan.title.secondary == nil, "a partial period is never the title")
        #expect(plan.limitations.contains(.undated(2)))
        #expect(plan.limitations.contains(.unplaced(3)))

        let none = fixture.engine.plan(IntelligenceRequest(pool: ["undated-0", "undated-1"], target: .collage))
        #expect(none.period.kind == .unknown)
        #expect(none.period.label(calendar: testCalendar) == nil)
    }

    @Test func exactDuplicatesAreExcluded() {
        let start = date(2026, 3, 3, 9)
        let shots = (0..<4).map { IntelligenceFixture.Shot(id: "p-\($0)", date: start.addingTimeInterval(Double($0) * 900), look: IntelligenceFixture.look($0)) }
            + [IntelligenceFixture.Shot(id: "copy-of-p-0", date: start.addingTimeInterval(86_400), look: IntelligenceFixture.look(0), megapixelsScale: 0.1)]
        let fixture = IntelligenceFixture(moments: [.init(key: "dup", title: "March Morning", shots: shots, duplicates: ["copy-of-p-0"])])
        let plan = fixture.engine.plan(IntelligenceRequest(pool: shots.map(\.id), target: .book, limit: 40))
        #expect(!plan.selected.contains("copy-of-p-0"))
        #expect(plan.excludedDuplicates == ["copy-of-p-0"])

        // A copy picked from the photo library (outside the story) is caught too.
        var library = IntelligenceFixture(moments: [.init(key: "dup", title: "March Morning", shots: Array(shots.prefix(4)))]).library
        let copy = IntelligenceFixture.asset(shots[4])
        library = library.addingPhotoLibraryAssets([copy])
        let outside = MemoryIntelligenceEngine(library: library).plan(IntelligenceRequest(pool: shots.map(\.id), target: .book))
        #expect(outside.excludedDuplicates == ["copy-of-p-0"])
        #expect(outside.selected.count == 4)
    }

    @Test func nearDuplicateRepresentativeIsDeterministic() {
        let fixture = IntelligenceFixture.burstHeavy()
        let first = fixture.engine.plan(for: .moment(IntelligenceFixture.momentID("burst")), target: .story)
        let second = fixture.engine.plan(for: .moment(IntelligenceFixture.momentID("burst")), target: .story)
        #expect(first == second)
        // The highest-quality selfie stands for the burst (quality falls slightly with each shot).
        #expect(first.selected.contains("selfie-0"))
    }

    @Test func sequencesStayInTheOrderTheyWereTaken() {
        let fixture = IntelligenceFixture.mixedTrip()
        let plan = fixture.engine.plan(for: .trip(IntelligenceFixture.tripID("Kaş & Kekova")), target: .story)
        let body = Array(plan.sequence.ordered.dropFirst())
        let dates = body.compactMap { fixture.library.assets[$0]?.creationDate }
        #expect(dates == dates.sorted(), "only the lead moves to the front")
        #expect(plan.sequence.ordered.first == plan.lead)
        #expect(plan.sequence.closer == body.last)
        let selectedDates = plan.selected.compactMap { fixture.library.assets[$0]?.creationDate }
        #expect(selectedDates == selectedDates.sorted())
    }

    @Test func hiddenMemoriesNeverAppear() {
        var fixture = IntelligenceFixture.mixedYears()
        fixture.moments[1].hidden = true
        let ids = fixture.moments.flatMap(\.shots).map(\.id)
        let plan = fixture.engine.plan(IntelligenceRequest(pool: ids, target: .book))
        #expect(!plan.selected.contains { $0.hasPrefix("aug") })
        #expect(!plan.alternates.contains { $0.hasPrefix("aug") })
        #expect(plan.limitations.contains(.hidden(3)))
    }

    @Test func unavailableAndUnknownPhotosDontCrash() {
        var fixture = IntelligenceFixture.smallMoment()
        fixture.unavailable = ["small-1"]
        let plan = fixture.engine.plan(IntelligenceRequest(pool: ["small-0", "small-1", "small-2", "never-imported"], target: .collage))
        #expect(plan.selected == ["small-0", "small-2"])
        #expect(plan.limitations.contains(.missing(2)))
        #expect(plan.sourceCount == 4)

        let empty = fixture.engine.plan(IntelligenceRequest(pool: ["never-imported"], target: .story))
        #expect(empty.status == .insufficient(available: 0, required: 3))
        #expect(empty.lead == nil)
        #expect(empty.title.primary == "Our Memories")
    }
}

// MARK: - User intent

@Suite("Memory intelligence: user intent")
struct MemoryIntelligenceUserIntentTests {
    @Test func chosenPhotosAreNeverSwapped() {
        let fixture = IntelligenceFixture.burstHeavy()
        let chosen = ["landscape-1", "selfie-3", "selfie-4", "couple"]
        let plan = fixture.engine.plan(for: .photos(chosen), target: .collage)
        #expect(plan.selected == chosen, "the user's photos, in the user's order")
        #expect(plan.collapsedSimilar.isEmpty && plan.excludedDuplicates.isEmpty)
        #expect(plan.nearDuplicateSelections == [["selfie-3", "selfie-4"]], "reported, not removed")
        #expect(Set(plan.sequence.ordered) == Set(chosen))
    }

    @Test func theUsersCoverLeads() {
        var fixture = IntelligenceFixture.smallMoment()
        fixture.moments[0].userCover = "small-0"
        let plan = fixture.engine.plan(for: .moment(IntelligenceFixture.momentID("small")), target: .story)
        #expect(plan.lead == "small-0")
        #expect(plan.leadReason == .userCover)

        let book = fixture.engine.plan(IntelligenceRequest(pool: (0..<5).map { "small-\($0)" }, target: .book, preferredLead: "small-3"))
        #expect(book.lead == "small-3")
        #expect(book.leadReason == .userChoice)
    }

    @Test func requiredPhotosStandForTheirCluster() {
        let fixture = IntelligenceFixture.burstHeavy()
        let plan = fixture.engine.plan(IntelligenceRequest(pool: fixture.moments[0].shots.map(\.id), target: .collage, required: ["selfie-9"]))
        #expect(plan.selected.contains("selfie-9"))
        #expect(plan.selected.filter { $0.hasPrefix("selfie") } == ["selfie-9"])
    }

    @Test func tooFewDistinctPhotosMayRepeatAndSaySo() {
        let start = date(2026, 1, 1, 0, 30)
        let shots = (0..<5).map { IntelligenceFixture.Shot(id: "nye-\($0)", date: start.addingTimeInterval(Double($0) * 15), look: IntelligenceFixture.near(0, drift: Float($0) * 0.01)) }
        let fixture = IntelligenceFixture(moments: [.init(key: "nye", title: "New Year's Eve", shots: shots)])
        let plan = fixture.engine.plan(for: .moment(IntelligenceFixture.momentID("nye")), target: .story)
        #expect(plan.selected.count == 3)
        #expect(plan.isReady)
        #expect(plan.limitations.contains(.repeatedSimilar(2)))
    }
}

// MARK: - Period and titles

@Suite("Memory intelligence: periods and factual titles")
struct PeriodAndTitleTests {
    private func period(_ dates: [Date?], place: String? = nil) -> PeriodDescriptor {
        let shots = dates.enumerated().map { IntelligenceFixture.Shot(id: "x-\($0.offset)", date: $0.element, look: IntelligenceFixture.look($0.offset)) }
        let fixture = IntelligenceFixture(moments: [.init(key: "p", title: "", shots: shots, place: place)])
        return PeriodDescriptor(candidates: MemoryCandidate.build(shots.map(\.id), library: fixture.library))
    }

    @Test func labels() {
        #expect(period([date(2026, 6, 8)]).label(calendar: testCalendar) == "June 8, 2026")
        #expect(period([date(2026, 6, 8), date(2026, 6, 10)]).label(calendar: testCalendar) == "June 8–10, 2026")
        #expect(period([date(2026, 8, 1), date(2026, 8, 29)]).label(calendar: testCalendar) == "August 2026")
        #expect(period([date(2026, 8, 3), date(2026, 10, 8)]).label(calendar: testCalendar) == "August – October 2026")
        #expect(period([date(2025, 4, 12), date(2026, 9, 18)]).label(calendar: testCalendar) == "2025 – 2026")
    }

    @Test func midnightStaysInItsOwnMonthAndYear() {
        // 23:59 on Dec 31 and 00:10 on Jan 1 in the library calendar (UTC+3).
        let p = period([date(2025, 12, 31, 23, 59), date(2026, 1, 1, 0, 10)])
        #expect(p.kind == .years(first: 2025, last: 2026))
    }

    @Test func seasonsOnlyWhenTheHemisphereIsKnown() {
        let summer = period([date(2026, 6, 20), date(2026, 8, 10)])
        #expect(summer.seasonLabel(hemisphere: nil) == nil, "Relive never assumes a hemisphere")
        #expect(summer.seasonLabel(hemisphere: .northern) == "Summer 2026")
        #expect(summer.seasonLabel(hemisphere: .southern) == "Winter 2026")
        #expect(period([date(2026, 5, 20), date(2026, 7, 10)]).seasonLabel(hemisphere: .northern) == nil, "spans two seasons")
    }

    @Test func titlesFollowTheRules() {
        let builder = FactualTitleBuilder(calendar: testCalendar)
        func title(_ dates: [Date], place: String? = nil) -> FactualTitle {
            let shots = dates.enumerated().map { IntelligenceFixture.Shot(id: "t-\($0.offset)", date: $0.element, look: IntelligenceFixture.look($0.offset)) }
            // Two moments, so the moment name isn't the title; the place (if any) is shared.
            let half = max(1, shots.count / 2)
            let fixture = IntelligenceFixture(moments: [
                .init(key: "a", title: "First", shots: Array(shots.prefix(half)), place: place),
                .init(key: "b", title: "Second", shots: Array(shots.dropFirst(half)), place: place),
            ])
            let candidates = MemoryCandidate.build(shots.map(\.id), library: fixture.library)
            return builder.title(for: candidates, period: PeriodDescriptor(candidates: candidates), story: fixture.library.story)
        }
        #expect(title([date(2026, 8, 2), date(2026, 8, 25)]).combined == "Moments from August · August 2026")
        #expect(title([date(2026, 8, 2), date(2026, 10, 25)]).combined == "Our 2026 · August – October 2026")
        #expect(title([date(2025, 8, 2), date(2026, 1, 5)]).combined == "Our Memories · 2025 – 2026")
        #expect(title([date(2025, 8, 2), date(2025, 8, 20)], place: "Bergama").combined == "Bergama · August 2025")
        #expect(builder.title(for: [], period: PeriodDescriptor(candidates: []), story: .empty).primary == "Our Memories")
    }

    @Test func noGeneratedTitleClaimsAFeeling() {
        let fixtures = [IntelligenceFixture.smallMoment(), .burstHeavy(), .mixedTrip(), .mixedYears()]
        for fixture in fixtures {
            let ids = fixture.moments.flatMap(\.shots).map(\.id)
            for target in [IntelligenceTarget.collage, .story, .book] {
                let plan = fixture.engine.plan(IntelligenceRequest(pool: ids, target: target))
                #expect(FactualTextPolicy.isFactual(plan.title.combined), "\(plan.title.combined)")
            }
        }
        #expect(FactualTextPolicy.violations(in: "Our happiest summer") == ["happiest"])
        #expect(!FactualTextPolicy.isFactual("The trip we'll never forget"))
        #expect(!FactualTextPolicy.isFactual("Our favorite place"))
        #expect(FactualTextPolicy.isFactual("Bergama · August 2025"))
    }

    @Test func userWordsWin() {
        let fixture = IntelligenceFixture.mixedYears()
        let plan = fixture.engine.plan(IntelligenceRequest(pool: fixture.moments.flatMap(\.shots).map(\.id), target: .book, userTitle: "Us, so far"))
        #expect(plan.title.primary == "Us, so far")
        #expect(plan.title.basis == .user)
    }
}

// MARK: - Recommendations, recency, diagnostics, performance

@Suite("Memory intelligence: plans")
struct MemoryIntelligencePlanTests {
    @Test func recommendationsFitTheBuilders() {
        let small = IntelligenceFixture.smallMoment().engine.plan(for: .moment(IntelligenceFixture.momentID("small")), target: .collage)
        #expect(small.recommendations.map(\.kind).contains(.collage))
        #expect(!small.recommendations.map(\.kind).contains(.book), "five photos aren't a book")
    }

    @Test func olderMemoriesAreNotWorse() {
        let recent = IntelligenceFixture.mixedTrip(year: 2026).engine.plan(for: .trip(IntelligenceFixture.tripID("Kaş & Kekova")), target: .collage)
        let old = IntelligenceFixture.mixedTrip(year: 2012).engine.plan(for: .trip(IntelligenceFixture.tripID("Kaş & Kekova")), target: .collage)
        #expect(recent.selected == old.selected, "the same photos ten years earlier are chosen the same way")
        #expect(recent.lead == old.lead)
    }

    @Test func diagnosticsSayWhyWithoutPrivateData() {
        final class Lines: @unchecked Sendable {
            let lock = NSLock()
            var values: [String] = []
        }
        let lines = Lines()
        IntelligenceDiagnostics.setSink { line in lines.lock.withLock { lines.values.append(line) } }
        defer { IntelligenceDiagnostics.setSink(nil) }
        let fixture = IntelligenceFixture.burstHeavy()
        let plan = fixture.engine.plan(for: .moment(IntelligenceFixture.momentID("burst")), target: .collage)
        let line = plan.diagnosticsLine
        #expect(line.hasPrefix("intelligence_plan target=collage mode=automatic source=18 selected=4"))
        #expect(line.contains("similarCollapsed=14"))
        #expect(line.contains("period=2026-07-04"))
        #expect(line.contains("leadReason="))
        #expect(!line.contains("selfie") && !line.contains("couple"), "no identifiers")
        #expect(lines.lock.withLock { lines.values.contains(line) })
    }

    @Test func plansRoundTripAsJSON() throws {
        let plan = IntelligenceFixture.mixedTrip().engine.plan(for: .trip(IntelligenceFixture.tripID("Kaş & Kekova")), target: .story)
        let data = try JSONEncoder().encode(plan)
        #expect(try JSONDecoder().decode(MemorySelectionPlan.self, from: data) == plan)
    }

    @Test func fiveHundredMemoriesPlanQuickly() {
        let start = date(2024, 1, 1, 10)
        var specs: [IntelligenceFixture.MomentSpec] = []
        for momentIndex in 0..<50 {
            var shots: [IntelligenceFixture.Shot] = []
            for index in 0..<10 {
                let offset = Double(momentIndex) * 86_400 * 3 + Double(index) * 120
                let look: [Float] = index < 4
                    ? IntelligenceFixture.near(momentIndex, drift: Float(index) * 0.01)
                    : IntelligenceFixture.look(momentIndex + index * 7)
                let quality = 0.3 + Double(index % 5) / 10
                shots.append(IntelligenceFixture.Shot(id: "perf-\(momentIndex)-\(index)", date: start.addingTimeInterval(offset),
                                                      portrait: index % 2 == 0, look: look, quality: quality))
            }
            specs.append(IntelligenceFixture.MomentSpec(key: "perf-\(momentIndex)", title: "Moment \(momentIndex)", shots: shots))
        }
        let fixture = IntelligenceFixture(moments: specs)
        let library = fixture.library
        let ids: [AssetID] = specs.flatMap { $0.shots.map { $0.id } }
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for target in [IntelligenceTarget.collage, .story, .book] {
                let plan = MemoryIntelligenceEngine(library: library).plan(IntelligenceRequest(pool: ids, target: target))
                #expect(plan.isReady)
            }
        }
        #expect(elapsed < .seconds(3), "500 memories × 3 plans took \(elapsed)")
    }
}

// MARK: - Integration with the existing creation logic

@Suite("Memory intelligence: creations")
struct MemoryIntelligenceIntegrationTests {
    @Test func favoritesCollageHasNoNearDuplicates() {
        // Favorites keep every favorited shot (they're never collapsed in the moment), so a
        // couple who favorited three takes of one selfie used to get all three.
        let start = date(2026, 4, 2, 18)
        var shots = (0..<3).map { IntelligenceFixture.Shot(id: "take-\($0)", date: start.addingTimeInterval(Double($0) * 8), favorite: true, look: IntelligenceFixture.near(0, drift: Float($0) * 0.02), quality: 0.6) }
        shots += (0..<3).map { IntelligenceFixture.Shot(id: "fav-\($0)", date: start.addingTimeInterval(3_600 * Double($0 + 1)), favorite: true, look: IntelligenceFixture.look($0 + 10)) }
        let library = IntelligenceFixture(moments: [.init(key: "f", title: "April Evening", shots: shots)]).library
        let picked = library.initialPhotos(for: .favorites, limit: CreationLimits.collagePreselection)
        #expect(picked.filter { $0.hasPrefix("take") }.count == 1, "\(picked)")
        #expect(picked.count == 4)
    }

    @Test func tripCreationsRepresentEveryDay() {
        let fixture = IntelligenceFixture.mixedTrip()
        let picked = fixture.library.initialPhotos(for: .trip(IntelligenceFixture.tripID("Kaş & Kekova")), limit: CreationLimits.collagePreselection)
        let moments = Set(picked.compactMap { fixture.library.moment(containing: $0)?.id })
        #expect(moments.count == 3)
        let dates = picked.compactMap { fixture.library.assets[$0]?.creationDate }
        #expect(dates == dates.sorted())
    }

    @Test func storiesFromABurstAreNotRepetitive() throws {
        let fixture = IntelligenceFixture.burstHeavy()
        let design = try StoryDesigner(library: fixture.library).design(source: .moment(IntelligenceFixture.momentID("burst")), style: .minimal).get()
        let photos = design.cards.flatMap(\.photos)
        #expect(photos.filter { $0.hasPrefix("selfie") }.count == 1, "\(photos)")
        // The user's own photos are never swapped.
        let chosen = ["selfie-1", "selfie-2", "selfie-3", "landscape-0"]
        let mine = try StoryDesigner(library: fixture.library).design(source: .photos(chosen), style: .minimal).get()
        #expect(Set(mine.cards.flatMap(\.photos)) == Set(chosen))
    }

    @Test func bookCoverUsesTheSharedLeadButTheUsersCoverWins() throws {
        var fixture = IntelligenceFixture.smallMoment()
        fixture.moments[0].shots[1].favorite = true
        fixture.moments[0].shots.append(.init(id: "small-5", date: date(2026, 6, 8, 18), look: IntelligenceFixture.look(30)))
        let library = fixture.library
        var book = try MemoryBookBuilder(library: library).makeBook(from: .moment(IntelligenceFixture.momentID("small")), now: date(2026, 10, 13)).get()
        #expect(book.photoIDs.count == 6)
        #expect(BookLayoutEngine(library: library).layout(book).pages.first?.slots.first?.assetID == "small-1", "the favorite leads the cover")
        _ = book.setCover("small-4")
        #expect(BookLayoutEngine(library: library).layout(book).pages.first?.slots.first?.assetID == "small-4", "the user's cover wins")
    }
}

@Suite("Memory intelligence: minimums")
struct MemoryIntelligenceMinimumTests {
    /// Regression (simulator CI): a moment whose featured photos still look alike (Relive's
    /// star grouping can leave two look-alikes featured) must not become "not enough photos".
    @Test func lookAlikeMomentsStillStartACollageStoryAndBook() throws {
        let start = date(2026, 3, 1, 12)
        let shots = (0..<6).map { IntelligenceFixture.Shot(id: "alike-\($0)", date: start.addingTimeInterval(Double($0) * 20), look: IntelligenceFixture.near(0, drift: Float($0) * 0.02)) }
        let fixture = IntelligenceFixture(moments: [.init(key: "alike", title: "March Afternoon", shots: shots)])
        let library = fixture.library
        let source = CreationSource.moment(IntelligenceFixture.momentID("alike"))

        let collage = library.initialPhotos(for: source, limit: CreationLimits.collagePreselection)
        #expect(collage.count >= CreationLimits.collage.lowerBound)
        #expect(collage.count >= CreationLimits.story.lowerBound)
        let story = try StoryDesigner(library: library).design(source: source, style: .minimal).get()
        #expect(story.cards.flatMap(\.photos).count >= CreationLimits.story.lowerBound)
        let book = try MemoryBookBuilder(library: library).makeBook(from: source, now: date(2026, 10, 13)).get()
        #expect(book.photoIDs.count >= BookLimits.minimumPhotos)
    }

    @Test func twoPhotoMomentsStillMakeACollage() {
        let start = date(2026, 3, 1, 12)
        let shots = (0..<2).map { IntelligenceFixture.Shot(id: "pair-\($0)", date: start.addingTimeInterval(Double($0) * 20), look: IntelligenceFixture.near(0, drift: Float($0) * 0.02)) }
        let library = IntelligenceFixture(moments: [.init(key: "pair", title: "March Afternoon", shots: shots)]).library
        #expect(library.initialPhotos(for: .moment(IntelligenceFixture.momentID("pair")), limit: CreationLimits.collagePreselection).count == 2)
    }
}
