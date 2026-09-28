import Foundation
import Testing
@testable import ReliveCore

/// A small but realistic library: everyday evenings at home, a trip to Kaş with a day in
/// Kekova, a WhatsApp copy of a trip photo, a few scattered singles and an undated scan.
enum LibraryFixture {
    static let copyHash: UInt64 = 0x0F0F_3C3C_A5A5_5A5A

    static func assets() -> [MemoryAsset] {
        var assets: [MemoryAsset] = []

        // Home: an evening each month, January–June.
        for month in 1...6 {
            assets += burst(from: date(2025, month, 10, 19), minutes: [0, 3, 9, 20, 41], location: Places.kadikoy, prefix: "home-\(month)")
        }

        // Kaş trip, August 6–9. Kekova on the 8th.
        assets += burst(from: date(2025, 8, 6, 18), minutes: [0, 10, 25, 50], location: Places.kas, prefix: "kas-arrival")
        assets += burst(from: date(2025, 8, 7, 11), minutes: [0, 5, 30, 90, 150], location: Places.kas, prefix: "kas-beach")
        assets += burst(from: date(2025, 8, 8, 10), minutes: [0, 20, 60, 100], location: Places.kekova, prefix: "kekova")
        assets += burst(from: date(2025, 8, 9, 9), minutes: [0, 15, 40], location: Places.kasHarbour, prefix: "kas-last")

        // The original of a favourite trip photo, and its WhatsApp copy saved days later.
        assets.append(makeAsset(
            "kas-original", at: date(2025, 8, 7, 12, 10), location: Places.kas, width: 4032, height: 3024,
            analysis: analysis(hash: copyHash, contrast: 0.4)
        ))
        assets.append(makeAsset(
            "kas-whatsapp-copy", at: date(2025, 8, 14, 21, 3), width: 1600, height: 1200,
            analysis: analysis(hash: copyHash ^ 0b101, contrast: 0.4)
        ))

        // Scattered singles in March 2025, no location.
        assets.append(makeAsset("march-a", at: date(2025, 3, 3, 13)))
        assets.append(makeAsset("march-b", at: date(2025, 3, 15, 20)))
        assets.append(makeAsset("march-c", at: date(2025, 3, 27, 9)))

        // A scanned print without a date and a video from the trip.
        assets.append(makeAsset("scan", at: nil))
        assets.append(makeAsset("kas-video", at: date(2025, 8, 7, 11, 40), location: Places.kas, kind: .video))
        return assets
    }
}

@Suite("MemoryEngine")
struct MemoryEngineTests {
    @Test("Builds moments, a trip chapter, a collection and an undated moment")
    func endToEnd() async throws {
        let input = LibraryFixture.assets()
        let result = try await makeEngine().buildStory(from: input.shuffled(), now: date(2026, 9, 28))
        let story = result.story

        #expect(result.assets.count == input.count)

        // Six home evenings, four trip days, one March collection, one undated.
        #expect(story.moments.count == 12)
        #expect(story.chapters.count == 1)

        let chapter = try #require(story.chapters.first)
        #expect(chapter.place?.name == "Kaş")
        #expect(chapter.title.primary == "Kaş")
        #expect(chapter.momentIDs.count == 4)
        let tripMoments = story.moments.filter { $0.chapterID == chapter.id }
        #expect(tripMoments.contains { $0.title.primary == "Kekova" })

        let collection = try #require(story.moments.first { $0.kind == .collection })
        #expect(collection.assetIDs == ["march-a", "march-b", "march-c"])
        #expect(collection.title.primary == "Moments from March")

        let undated = try #require(story.moments.last)
        #expect(undated.kind == .undated)
        #expect(undated.assetIDs == ["scan"])

        // Everyday life at home is named by time; the place stays on the moment.
        let homeMoment = try #require(story.moments.first)
        #expect(homeMoment.title == MomentTitle(primary: "January Evening", secondary: "January 2025"))
        #expect(homeMoment.place?.name == "Kadıköy")
        #expect(homeMoment.heroAssetID != nil)
    }

    @Test("A WhatsApp copy joins its original's moment instead of creating a new one")
    func duplicateCopyAttached() async throws {
        let result = try await makeEngine().buildStory(from: LibraryFixture.assets(), now: date(2026, 9, 28))
        let owner = try #require(result.story.moments.first { $0.assetIDs.contains("kas-original") })
        #expect(owner.assetIDs.contains("kas-whatsapp-copy"))
        #expect(owner.duplicateAssetIDs == ["kas-whatsapp-copy"])
        #expect(!owner.featuredAssetIDs.contains("kas-whatsapp-copy"))
        #expect(owner.endDate ?? .distantFuture < date(2025, 8, 8))
        #expect(result.diagnostics.duplicateCount == 1)
    }

    @Test("Progress is reported in order and ends finished")
    func progressOrder() async throws {
        let recorder = ProgressRecorder()
        _ = try await makeEngine().buildStory(from: LibraryFixture.assets(), now: date(2026, 9, 28)) { recorder.record($0) }
        let stages = recorder.values.map(\.stage)
        #expect(stages.first == .readingMetadata)
        #expect(stages.last == .finished)
        #expect(stages == stages.sorted())
        let analysisUpdates = recorder.values.filter { $0.stage == .analyzingImages }
        #expect(analysisUpdates.last?.completedUnits == analysisUpdates.last?.totalUnits)
        let fractions = recorder.values.map(\.overallFraction)
        #expect(fractions == fractions.sorted())
    }

    @Test("Works without locations, without analysis and with failures")
    func degradesGracefully() async throws {
        let input = LibraryFixture.assets().map { asset -> MemoryAsset in
            var copy = asset
            copy.location = nil
            copy.analysis = nil
            return copy
        }
        let failing = Set(input.prefix(10).map(\.id))
        let engine = makeEngine(analyzer: FakeAnalyzer(failingIDs: failing), placeResolver: NoPlaceNameResolver())
        let result = try await engine.buildStory(from: input, now: date(2026, 9, 28))
        #expect(!result.story.moments.isEmpty)
        #expect(result.story.chapters.isEmpty)
        #expect(result.story.moments.allSatisfy { $0.place == nil && !$0.title.primary.isEmpty })
        #expect(result.story.moments.allSatisfy { $0.heroAssetID != nil })
        #expect(result.diagnostics.analysisFailureCount == 10)
    }

    @Test("Cached analysis is not recomputed")
    func cachedAnalysisReused() async throws {
        let first = try await makeEngine().buildStory(from: LibraryFixture.assets(), now: date(2026, 9, 28))
        let recorder = ProgressRecorder()
        _ = try await makeEngine().buildStory(from: first.assets, now: date(2026, 9, 28)) { recorder.record($0) }
        let analysisTotal = recorder.values.first { $0.stage == .analyzingImages }?.totalUnits
        #expect(analysisTotal == 0)
    }

    @Test("Same input, same story")
    func deterministic() async throws {
        let assets = LibraryFixture.assets()
        let first = try await makeEngine().buildStory(from: assets, now: date(2026, 9, 28))
        let second = try await makeEngine().buildStory(from: assets.reversed(), now: date(2026, 9, 28))
        #expect(first.story == second.story)
    }

    @Test("An empty selection produces an empty story")
    func empty() async throws {
        let result = try await makeEngine().buildStory(from: [], now: date(2026, 9, 28))
        #expect(result.story.isEmpty)
    }

    @Test("Cancellation stops the pipeline")
    func cancellation() async {
        let task = Task {
            try await makeEngine().buildStory(from: LibraryFixture.assets(), now: date(2026, 9, 28))
        }
        task.cancel()
        let result = await task.result
        switch result {
        case .success: Issue.record("Expected cancellation")
        case .failure(let error): #expect(error is CancellationError)
        }
    }
}

@Suite("Story presentation")
struct StoryPresentationTests {
    @Test("Statistics count distinct memories, moments and places")
    func statistics() async throws {
        let result = try await makeEngine().buildStory(from: LibraryFixture.assets(), now: date(2026, 9, 28))
        let assets = Dictionary(uniqueKeysWithValues: result.assets.map { ($0.id, $0) })
        let stats = StoryStatistics.compute(story: result.story, assets: assets, userStates: [:], isAvailable: { _ in true })
        let input = LibraryFixture.assets()
        #expect(stats.memoryCount == input.count - 1) // the WhatsApp copy isn't a separate memory
        #expect(stats.videoCount == 1)
        #expect(stats.momentCount == 12)
        #expect(stats.placeCount == 3) // Kadıköy, Kaş, Kekova

        let hiddenID = try #require(result.story.moments.first?.id)
        let hidden = StoryStatistics.compute(
            story: result.story, assets: assets, userStates: [hiddenID: MomentUserState(isHidden: true)], isAvailable: { _ in true }
        )
        #expect(hidden.momentCount == 11)
        #expect(hidden.memoryCount == stats.memoryCount - 5)
    }

    @Test("Timeline groups by year and nests trips")
    func timeline() async throws {
        let result = try await makeEngine().buildStory(from: LibraryFixture.assets(), now: date(2026, 9, 28))
        let sections = TimelineBuilder(calendar: testCalendar).sections(for: result.story) { _ in true }
        #expect(sections.map(\.title) == ["2025", "Without a date"])
        let chapters = sections[0].items.filter { if case .chapter = $0 { true } else { false } }
        #expect(chapters.count == 1)
        #expect(chapters.first?.moments.count == 4)
        // 6 home evenings + March collection + the trip = 8 items in 2025.
        #expect(sections[0].items.count == 8)
    }

    @Test("A trip with one visible moment shows as that moment")
    func hiddenTripMoments() async throws {
        let result = try await makeEngine().buildStory(from: LibraryFixture.assets(), now: date(2026, 9, 28))
        let chapter = try #require(result.story.chapters.first)
        let keep = chapter.momentIDs[0]
        let sections = TimelineBuilder(calendar: testCalendar).sections(for: result.story) { moment in
            moment.chapterID != chapter.id || moment.id == keep
        }
        let hasChapter = sections.flatMap(\.items).contains { if case .chapter = $0 { true } else { false } }
        #expect(!hasChapter)
        #expect(sections.flatMap(\.items).contains { $0.id == "moment-\(keep.uuidString)" })
    }

    @Test("Days together respects the calendar")
    func daysTogether() {
        let start = RelationshipStart(date: date(2022, 5, 1), precision: .month)
        #expect(start.daysTogether(until: date(2026, 9, 28), calendar: testCalendar) == 1611)
        #expect(start.isApproximate)
        #expect(RelationshipProfile(partnerName: "Emma").coupleDisplayName == "You + Emma")
        #expect(RelationshipProfile(partnerName: "Emma", userName: "Jake").coupleDisplayName == "Jake + Emma")
    }
}
