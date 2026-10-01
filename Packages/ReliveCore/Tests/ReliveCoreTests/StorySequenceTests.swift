import Foundation
import Testing
@testable import ReliveCore

@Suite("Story Maker sequences")
struct StorySequenceTests {
    let fixture = CreationFixture.make()

    func build(_ source: CreationSource, excluding: Set<AssetID> = [], library: CreationLibrary? = nil) throws -> StorySequence {
        try StorySequenceBuilder(library: library ?? fixture.library).sequence(for: source, excluding: excluding).get()
    }

    @Test("A moment becomes an opening card plus photos, 3–6 cards in all")
    func moment() throws {
        let kas = fixture.moment("kas")
        let sequence = try build(.moment(kas.id))
        #expect((3...6).contains(sequence.cards.count))
        #expect(sequence.cards.count == 6)
        #expect(sequence.cards[0].kind == .opening)
        #expect(sequence.cards[0].assetID == kas.heroAssetID)
        #expect(sequence.cards[0].title == .named("Kaş"))
        #expect(sequence.cards[0].place?.name == "Kaş")
        #expect(Set(sequence.photoIDs).count == sequence.photoIDs.count, "no photo twice")
        #expect(Set(sequence.photoIDs).isSubset(of: Set(kas.assetIDs)))
        // One day, one place: no repeated captions on the photo cards.
        #expect(sequence.cards.dropFirst().allSatisfy { $0.kind == .photo && $0.title == nil })
    }

    @Test("Small moments give fewer cards; too-small ones explain why")
    func sizes() throws {
        let kekova = try build(.moment(fixture.moment("kekova").id))
        #expect(kekova.cards.count == 4, "4 usable photos → 4 cards; the screenshot is left out")
        #expect(!kekova.photoIDs.contains("kekova-shot"))

        let result = StorySequenceBuilder(library: fixture.library).sequence(for: .moment(fixture.moment("afternoon").id))
        #expect(result == .failure(.notEnoughPhotos(available: 2, required: 3)))
    }

    @Test("Photos from different moments get the moment's name and day — only when it changes")
    func memoryCards() throws {
        let sequence = try build(.photos(["moda-0", "moda-1", "kekova-0", "kekova-1", "coffee-0"]))
        let memory = sequence.cards.filter { $0.kind == .memory }
        #expect(!memory.isEmpty)
        for card in memory {
            if case .named(let name)? = card.title {
                #expect(["Moda Evening", "Kekova", "Coffee"].contains(name))
            }
            #expect(card.dateSpan != nil)
        }
        #expect(sequence.facts.title == nil, "no shared moment, trip or place: no invented title")
        #expect(sequence.cards.count == 5)
    }

    @Test("Ten chosen photos become six cards spread across them")
    func capsAtSix() throws {
        let ids = (0..<8).map { "kas-\($0)" } + ["kekova-0", "kekova-1"]
        let sequence = try build(.photos(ids))
        #expect(sequence.cards.count == 6)
        #expect(sequence.facts.title == .named("Kaş"), "a trip's photos are titled with the trip")
    }

    @Test("A missing photo is replaced instead of breaking the story")
    func missingPhoto() throws {
        let kas = fixture.moment("kas")
        let first = try build(.moment(kas.id))
        let missing = first.cards[1].assetID!
        let second = try build(.moment(kas.id), excluding: [missing])
        #expect(!second.photoIDs.contains(missing))
        #expect(second.cards.count == 6)

        var fixture = fixture
        fixture.unavailable = Set(kas.assetIDs.dropFirst(2))
        let result = StorySequenceBuilder(library: fixture.library).sequence(for: .moment(kas.id))
        #expect(result == .failure(.notEnoughPhotos(available: 2, required: 3)))
    }

    @Test("A month story opens with the month and names each moment")
    func month() throws {
        let sequence = try build(.month(MonthKey(year: 2025, month: 9)))
        #expect(sequence.cards[0].title == .month(MonthKey(year: 2025, month: 9)))
        let names = sequence.cards.compactMap { card -> String? in
            if case .named(let name)? = card.title { return name }
            return nil
        }
        #expect(names.contains("Moda Evening") || names.contains("September Afternoon"))
        #expect((3...6).contains(sequence.cards.count))
    }

    @Test("A year story opens with the year, moves by month and closes")
    func year() throws {
        let sequence = try build(.year(2025))
        #expect(sequence.cards.first?.title == .year(2025))
        #expect(sequence.cards.last?.kind == .closing)
        #expect(sequence.cards.last?.assetID == nil)
        #expect(sequence.cards.count == 6)
        let months = sequence.cards.compactMap { card -> Int? in
            if case .month(let key)? = card.title { return key.month }
            return nil
        }
        #expect(months.allSatisfy { [8, 9].contains($0) })
    }

    @Test("Sequences are deterministic")
    func deterministic() throws {
        let a = try build(.year(2025))
        let b = try build(.year(2025))
        #expect(a == b)
    }

    @Test("A multi-day moment marks each new day")
    func days() throws {
        var fixture = fixture
        let kas = fixture.moment("kas")
        // Move the last three photos to the next day.
        for id in kas.assetIDs.suffix(3) {
            let moved = fixture.assets[id]?.creationDate?.addingTimeInterval(86_400)
            fixture.assets[id]?.creationDate = moved
        }
        let sequence = try build(.moment(kas.id), library: fixture.library)
        let memory = sequence.cards.filter { $0.kind == .memory }
        #expect(memory.count == 1)
        #expect(memory.first?.title == nil)
        #expect(memory.first?.dateSpan != nil)
    }
}

@Suite("Surprise Memory")
struct SurpriseMemoryTests {
    let fixture = CreationFixture.make()

    func service(_ fixture: CreationFixture? = nil) -> SurpriseMemoryService {
        SurpriseMemoryService(library: (fixture ?? self.fixture).library)
    }

    @Test("Anniversaries are exact: same day, within a few days, or not at all")
    func anchors() {
        let service = service()
        let photo = date(2025, 8, 6, 10)
        #expect(service.anchor(for: photo, now: date(2026, 8, 6, 8))! == (.years(1), true))
        #expect(service.anchor(for: photo, now: date(2026, 8, 9, 8))! == (.years(1), false))
        #expect(service.anchor(for: photo, now: date(2026, 8, 3, 8))! == (.years(1), false))
        #expect(service.anchor(for: photo, now: date(2026, 8, 10, 8)) == nil)
        #expect(service.anchor(for: photo, now: date(2027, 8, 6, 8))! == (.years(2), true))
        #expect(service.anchor(for: photo, now: date(2026, 2, 6, 8))! == (.months(6), true))
        #expect(service.anchor(for: photo, now: date(2026, 1, 6, 8)) == nil, "5 months is not offered")
        #expect(service.anchor(for: photo, now: date(2025, 8, 6, 20)) == nil, "today is not a memory yet")
    }

    @Test("A leap-day photo's anniversary falls on February 28 in other years")
    func leapDay() {
        let service = service()
        #expect(service.anchor(for: date(2024, 2, 29), now: date(2025, 2, 28))! == (.years(1), true))
        #expect(service.anchor(for: date(2024, 2, 29), now: date(2028, 2, 29))! == (.years(4), true))
    }

    @Test("Descriptions say exactly what was computed")
    func descriptions() {
        func memory(_ anchor: SurpriseAnchor, _ sameDay: Bool) -> String {
            SurpriseMemory(momentID: UUID(), assetID: "a", captureDate: Date(), anchor: anchor, isSameDay: sameDay, place: nil).ageDescription
        }
        #expect(memory(.years(1), true) == "A year ago today")
        #expect(memory(.years(3), false) == "3 years ago this week")
        #expect(memory(.months(6), true) == "6 months ago today")
    }

    @Test("Picks a memory from this week a year ago")
    func selects() throws {
        let surprise = try #require(service().select(now: date(2026, 8, 7, 9), lastSurpriseDay: nil))
        #expect([CreationFixture.momentID("kas"), CreationFixture.momentID("kekova")].contains(surprise.momentID))
        #expect(surprise.anchor == .years(1))
        #expect(surprise.assetID != "kekova-shot")
        // Same inputs, same answer.
        #expect(service().select(now: date(2026, 8, 7, 9), lastSurpriseDay: nil) == surprise)
    }

    @Test("Nothing on ordinary days")
    func ordinaryDay() {
        #expect(service().select(now: date(2026, 6, 20, 9), lastSurpriseDay: nil) == nil)
    }

    @Test("Rests between surprises")
    func rests() {
        let now = date(2026, 8, 7, 9)
        #expect(service().select(now: now, lastSurpriseDay: date(2026, 8, 5)) == nil)
        #expect(service().select(now: now, lastSurpriseDay: date(2026, 8, 3)) != nil)
    }

    @Test("Skips moments already on Today, shown recently, hidden or turned off")
    func eligibility() {
        let now = date(2026, 8, 7, 9)
        let kas = CreationFixture.momentID("kas")
        let kekova = CreationFixture.momentID("kekova")
        #expect(service().select(now: now, lastSurpriseDay: nil, excluding: [kas, kekova]) == nil)

        var fixture = fixture
        fixture.userStates[kas] = MomentUserState(isExcludedFromSurfacing: true)
        fixture.userStates[kekova] = MomentUserState(lastSurfacedAt: date(2026, 8, 1))
        #expect(service(fixture).select(now: now, lastSurpriseDay: nil) == nil)

        fixture.userStates[kekova] = MomentUserState(isHidden: true)
        #expect(service(fixture).select(now: now, lastSurpriseDay: nil) == nil)

        fixture.userStates[kekova] = MomentUserState(lastSurfacedAt: date(2026, 6, 1))
        #expect(service(fixture).select(now: now, lastSurpriseDay: nil)?.momentID == kekova)
    }

    @Test("Undated and unavailable photos are never surprises")
    func undatedUnavailable() {
        var fixture = fixture
        fixture.unavailable = Set(fixture.moment("kas").assetIDs + fixture.moment("kekova").assetIDs)
        #expect(service(fixture).select(now: date(2026, 8, 7, 9), lastSurpriseDay: nil) == nil)
    }

    @Test("Restores today's choice only while it is still true")
    func restore() {
        let kas = CreationFixture.momentID("kas")
        #expect(service().restore(momentID: kas, assetID: "kas-0", now: date(2026, 8, 6, 20)) != nil)
        #expect(service().restore(momentID: kas, assetID: "kas-0", now: date(2026, 9, 6, 20)) == nil)
        #expect(service().restore(momentID: kas, assetID: "kekova-0", now: date(2026, 8, 6, 20)) == nil)
    }
}
