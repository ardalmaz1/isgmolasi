import Foundation
import Testing
@testable import ReliveCore

/// Story Maker 2.0: Relive designs a sequence rather than putting each photo in a frame.
@Suite("Story designer")
struct StoryDesignerTests {
    let fixture = CreationFixture.make()

    private func design(_ source: CreationSource, style: StoryStyle = .minimal, variation: Int = 0) throws -> StoryDesign {
        try StoryDesigner(library: fixture.library).design(source: source, style: style, variation: variation).get()
    }

    private var sources: [CreationSource] {
        [
            .moment(fixture.moment("kas").id),
            .trip(CreationFixture.tripID),
            .month(MonthKey(year: 2025, month: 9)),
            .year(2025),
            .photos(["kas-0", "kas-3", "kekova-1", "moda-0", "moda-2", "coffee-1"]),
        ]
    }

    @Test("Every source makes 3–7 cards, with an opening first")
    func bounds() throws {
        for source in sources {
            for style in StoryStyle.allCases {
                for variation in 0..<3 {
                    let story = try design(source, style: style, variation: variation)
                    #expect(StoryDesigner.cardRange.contains(story.cards.count), "\(source) \(style) \(variation): \(story.cards.count)")
                    #expect(story.cards.first?.role == .opening)
                    #expect(story.cards.allSatisfy { $0.photos.count == $0.layout.photoCount }, "every layout shows its photos")
                }
            }
        }
    }

    @Test("Photo cards follow the order the photos were taken")
    func chronological() throws {
        for source in sources {
            let story = try design(source)
            let body = story.cards.filter { $0.role == .photo }.flatMap(\.photos)
            #expect(body == body.sorted(by: fixture.library.chronologicalOrder), "\(source)")
            #expect(Set(story.photoIDs).count == story.photoIDs.count, "no photo twice")
        }
    }

    @Test("Several photos share cards — a story is not one photo per card")
    func multiPhotoCards() throws {
        let story = try design(.trip(CreationFixture.tripID))
        #expect(story.cards.contains { $0.photos.count >= 2 })
        #expect(story.photoIDs.count > story.cards.filter { !$0.photos.isEmpty }.count)
    }

    @Test("The opening says what the photos are: their real name, dates and place")
    func factualOpening() throws {
        let kas = try design(.moment(fixture.moment("kas").id))
        #expect(kas.cards[0].title == .named("Kaş"))
        #expect(kas.cards[0].place?.name == "Kaş")
        let mixed = try design(.photos(["kas-0", "kas-1", "moda-0", "afternoon-0"]))
        #expect(mixed.cards[0].title == .year(2025), "August and September: not one of them")
        #expect(mixed.cards[0].place == nil, "Kaş and Kadıköy: no single place")
        let years = try design(.photos(["kas-0", "kas-1", "coffee-0", "coffee-1"]))
        #expect(years.cards[0].title == nil, "2025 and 2026: no single label")
    }

    @Test("The closing is factual: a year closes as a year only when it is one")
    func factualClosing() throws {
        let year = try design(.year(2025))
        #expect(year.cards.last?.role == .closing)
        #expect(year.cards.last?.closingYear == 2025)

        let moment = try design(.moment(fixture.moment("kas").id))
        #expect(moment.cards.last?.closingYear == nil)
        #expect(moment.cards.last?.place?.name == "Kaş")

        // Nothing known (no dates, no places): no closing card at all.
        let undatedPicks = (0..<4).map { makeAsset("u\($0)", at: nil) }
        let library = fixture.library.addingPhotoLibraryAssets(undatedPicks)
        let undated = try StoryDesigner(library: library).design(source: .photos(undatedPicks.map(\.id)), style: .minimal).get()
        #expect(!undated.cards.contains { $0.role == .closing })
        #expect(undated.cards.allSatisfy { $0.dateSpan == nil && $0.place == nil && $0.title == nil }, "nothing invented")
    }

    @Test("Each card describes only its own photos")
    func perCardFacts() throws {
        for source in sources {
            for card in try design(source).cards where card.role == .photo {
                let summary = fixture.library.metadata(of: card.photos)
                #expect(card.dateSpan == summary.dateSpan)
                #expect(card.place == summary.place)
            }
        }
    }

    @Test("A place card appears where the place really changes")
    func placeCards() throws {
        let trip = try design(.trip(CreationFixture.tripID))
        let places = trip.cards.filter { $0.role == .place }
        #expect(places.map(\.title) == [.named("Kekova")], "Kaş is the opening; Kekova begins later")
        let moment = try design(.moment(fixture.moment("kas").id))
        #expect(!moment.cards.contains { $0.role == .place }, "one place, no place card")
    }

    @Test("Styles are designs of their own, not just colours")
    func styleVariation() throws {
        let source = CreationSource.trip(CreationFixture.tripID)
        let layouts = Set(try StoryStyle.allCases.map { try design(source, style: $0).cards.map(\.layout) })
        #expect(layouts.count >= 3, "styles choose different compositions")
    }

    @Test("Make it for me makes a valid story and varies it deterministically")
    func makeItForMe() throws {
        let designer = StoryDesigner(library: fixture.library)
        let source = CreationSource.trip(CreationFixture.tripID)
        let first = try designer.makeItForMe(source: source, variation: 0).get()
        #expect(first.style == .travel, "a trip with a real place suits Travel")
        #expect(StoryDesigner.cardRange.contains(first.cards.count))
        #expect(try designer.makeItForMe(source: source, variation: 0).get() == first, "deterministic")
        let second = try designer.makeItForMe(source: source, variation: 1).get()
        #expect(second != first, "pressing again gives another design")
        #expect(StoryDesigner.cardRange.contains(second.cards.count))
        let styles = Set((0..<5).compactMap { try? designer.makeItForMe(source: source, variation: $0).get().style })
        #expect(styles.count == 5, "five presses go through every style")
    }

    @Test("Too few photos makes no story")
    func shortfall() {
        let designer = StoryDesigner(library: fixture.library)
        #expect(throws: CreationShortfall.self) { try designer.design(source: .moment(fixture.moment("afternoon").id), style: .minimal).get() }
    }

    @Test("Editing: change layout, replace a photo, remove a card")
    func editing() throws {
        var story = try design(.trip(CreationFixture.tripID))
        let pair = try #require(story.cards.first { $0.role == .photo && $0.photos.count == 2 })
        let ok1 = story.cycleLayout(of: pair.id)
        #expect(ok1)
        #expect(story.cards.first { $0.id == pair.id }?.layout != pair.layout)

        let replacement = try #require(fixture.library.usablePhotos(in: fixture.moment("moda")).first)
        let ok2 = story.replacePhoto(cardID: pair.id, slot: 1, with: replacement, library: fixture.library)
        #expect(ok2)
        let edited = try #require(story.cards.first { $0.id == pair.id })
        #expect(edited.photos[1] == replacement)
        #expect(edited.dateSpan == fixture.library.metadata(of: edited.photos).dateSpan, "facts follow the new photo")
        #expect(edited.place == nil, "Kaş and Kadıköy share no place")

        let ok3 = story.removeCard(0)
        #expect(!ok3, "the opening stays")
        let count = story.cards.count
        let ok4 = story.removeCard(pair.id)
        #expect(ok4)
        #expect(story.cards.count == count - 1)
    }

    @Test("Photo library photos tell their own dates in a story")
    func photoLibraryStory() throws {
        let picks = [
            makeAsset("l1", at: date(2026, 8, 30, 19)),
            makeAsset("l2", at: date(2026, 9, 5, 19), width: 4032, height: 3024),
            makeAsset("l3", at: date(2026, 9, 18, 19)),
            makeAsset("l4", at: date(2026, 10, 2, 19)),
        ]
        let library = fixture.library.addingPhotoLibraryAssets(picks)
        let story = try StoryDesigner(library: library).design(source: .photos(picks.map(\.id)), style: .film).get()
        #expect(story.cards[0].title == .year(2026))
        #expect(story.cards[0].dateSpan == DateSpan(start: date(2026, 8, 30, 19), end: date(2026, 10, 2, 19)))
        #expect(!story.cards.contains { $0.title == .month(MonthKey(year: 2026, month: 9)) })
    }
}
