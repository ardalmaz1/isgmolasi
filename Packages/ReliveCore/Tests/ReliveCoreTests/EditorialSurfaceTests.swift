import Foundation
import Testing
@testable import ReliveCore

/// Editorial intelligence on real surfaces: the Memory Movie opening title, Made for You, and the
/// user's control over Relive's words.
@Suite("Editorial: surfaces and the user's choice")
struct EditorialSurfaceTests {
    typealias M = MovieFixture
    typealias F = IntelligenceFixture

    @Test func movieOffersSafeTitleVariantsAndKeepsTheFactualOneFirst() {
        let plan = M.planner(M.fourDayTrip()).plan(source: .trip(F.tripID("Lycian Coast")))
        #expect(plan.titleVariants.first == "Lycian Coast")
        #expect(plan.titleVariants.contains("Four days in Lycian Coast."))
        #expect((2...3).contains(plan.titleVariants.count))
        // Relive's first choice looks exactly as before.
        #expect(plan.scenes.first?.text?.title == "Lycian Coast")
        #expect(plan.openingTitleAuthorship == .relive)
        // Every variant passes the shared validator and fits a movie frame.
        for text in plan.titleVariants {
            #expect(text.count <= 34, "\(text)")
            #expect(FactualTextPolicy.isFactual(text), "\(text)")
        }
    }

    @Test func tryAnotherRotatesAndTheUsersWordsWin() {
        let planner = M.planner(M.fourDayTrip())
        let source = CreationSource.trip(F.tripID("Lycian Coast"))
        let base = planner.plan(source: source)
        var settings = base.settings
        settings.titleChoice = EditorialChoice().next(in: base.titleVariants)
        let second = planner.plan(source: source, photos: base.photoIDs, cover: base.cover, settings: settings, isUserCut: false)
        #expect(second.scenes.first?.text?.title == base.titleVariants[1])
        #expect(second.scenes.first?.text?.eyebrow == "August 6–9, 2025")
        #expect(second.photoIDs == base.photoIDs, "words never change the photos")

        settings.titleChoice = EditorialChoice(userText: "  Our favorite trip  ")
        let own = planner.plan(source: source, photos: base.photoIDs, cover: base.cover, settings: settings, isUserCut: false)
        #expect(own.scenes.first?.text?.title == "Our favorite trip", "the user's words are kept, even a ranking")
        #expect(own.openingTitleAuthorship == .user)

        settings.titleChoice = EditorialChoice(isRemoved: true)
        let removed = planner.plan(source: source, photos: base.photoIDs, cover: base.cover, settings: settings, isUserCut: false)
        #expect(removed.openingTitle == nil)
        #expect(removed.scenes.first?.text?.title == "August 6–9, 2025")
    }

    @Test func choiceRoundTripsAndOldDraftsStillOpen() throws {
        let settings = MovieSettings(titleChoice: EditorialChoice(variant: 2, userText: "Bizim yaz"))
        let state = MovieState(photoIDs: [], cover: nil, settings: settings, isUserCut: true)
        let decoded = try JSONDecoder().decode(MovieState.self, from: JSONEncoder().encode(state))
        #expect(decoded.settings.titleChoice?.userText == "Bizim yaz")
        // A Phase 4 draft has no titleChoice.
        let encoded = try JSONEncoder().encode(MovieSettings())
        #expect(!String(decoding: encoded, as: UTF8.self).contains("titleChoice"))
        let oldSettings = try JSONDecoder().decode(MovieSettings.self, from: encoded)
        #expect(oldSettings.titleChoice == nil)
    }

    @Test func choiceResolution() {
        let variants = ["Kaş", "Four days in Kaş.", "Kaş · August 2026"]
        #expect(EditorialChoice().resolve(variants).text == "Kaş")
        #expect(EditorialChoice(variant: 4).resolve(variants).text == "Four days in Kaş.")
        #expect(EditorialChoice(variant: 2).next(in: variants).variant == 0)
        #expect(EditorialChoice().next(in: variants) == EditorialChoice(variant: 1, chosenText: "Four days in Kaş."))
        #expect(EditorialChoice(userText: "Bizim").next(in: variants).isDefault, "Try another after own words: Relive's first")
        // A chosen variant survives a change in what is on offer, while it is still true.
        let kept = EditorialChoice(variant: 1, chosenText: "Kaş, in August.")
        #expect(kept.resolve(variants, stillTrue: { _ in true }).text == "Kaş, in August.")
        #expect(kept.resolve(variants).text == "Four days in Kaş.")
        #expect(EditorialChoice(userText: "   ").resolve(variants).text == "Kaş", "blank is not the user's words")
        #expect(EditorialChoice(variant: 1, userText: "Bizim").resolve(variants) == ("Bizim", .user))
        #expect(EditorialChoice().resolve([]).text == nil)
    }

    @Test func aMixedYearMovieClaimsNoSingleYear() {
        let plan = M.planner(M.bigYear()).plan(source: .year(2026))
        for text in plan.titleVariants {
            #expect(!text.contains("2025"), "\(text)")
            #expect(FactualTextPolicy.isFactual(text), "\(text)")
        }
    }

    @Test func madeForYouTripWordingIsValidatedAndPlanUnchanged() {
        let fixture = IntelligenceFixture.mixedTrip()
        let suggestion = MadeForYouFixture.engine(fixture).trips().first
        #expect(suggestion?.title == "Three days in Kaş & Kekova.")
        #expect(suggestion?.creation == .movie, "words never change what is recommended")
        #expect(suggestion?.memoryCount == 30)
    }

    final class EventLog: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [EditorialEvent] = []
        func append(_ event: EditorialEvent) { lock.withLock { stored.append(event) } }
        var events: [EditorialEvent] { lock.withLock { stored } }
    }

    @Test func analyticsEventsCarryCodesOnlyAndCachedRequestsAreSilent() async {
        let pipeline = EditorialPipeline()
        let log = EventLog()
        pipeline.observe { log.append($0) }
        let request = EditorialRequest(context: EditorialFixture.kas(), kind: .title)
        let model = EditorialPipelineTests.FakeModel(replies: ["Kaş, in August.", "Five days in Kaş."])
        _ = await EditorialRouter(pipeline: pipeline, model: model).enhanced(request)
        _ = pipeline.result(for: request)
        let names = log.events.map(\.analyticsName)
        #expect(names.filter { $0 == .editorialRequested }.count == 1, "a redraw doesn't regenerate")
        #expect(names.contains(.editorialCandidateAccepted))
        #expect(names.contains(.editorialCandidateRejected))
        for event in log.events {
            for value in event.analyticsProperties.values {
                #expect(!value.contains("Kaş") && !value.contains("August") && !value.contains("days"), "\(value)")
            }
        }
        _ = await EditorialRouter(pipeline: pipeline, model: EditorialPipelineTests.FakeModel(available: false)).enhanced(EditorialRequest(context: EditorialFixture.kas(), kind: .subtitle))
        #expect(log.events.last?.analyticsName == .editorialFallbackUsed)
    }
}

@Suite("Editorial: on-device model prompt")
struct EditorialPromptTests {
    @Test func thePromptCarriesFactsOnlyAndTheReplyIsParsed() {
        var context = EditorialFixture.kas()
        context.userText = "Our secret note"
        let prompt = EditorialPrompt.prompt(for: EditorialRequest(context: context, kind: .title))
        #expect(prompt.contains("Kaş"))
        #expect(!prompt.contains("secret"), "the user's words are never sent to a model")
        #expect(EditorialPrompt.instructions(for: .turkish).contains("Turkish"))
        #expect(EditorialPrompt.lines(from: "1. \"Kaş, in August.\"\n- August in Kaş\n\n• Kaş") == ["Kaş, in August.", "August in Kaş", "Kaş"])
    }

    @Test func modelVariantsFollowRelivesFirstChoiceAndAreKept() async {
        let pipeline = EditorialPipeline()
        let request = EditorialRequest(context: EditorialFixture.kas(), kind: .title)
        let model = EditorialPipelineTests.FakeModel(replies: ["Kaş, in August."])
        let enhanced = await EditorialRouter(pipeline: pipeline, model: model).enhanced(request)
        #expect(enhanced.variants.count <= EditorialPipeline.maximumVariants)
        #expect(enhanced.variants[1] == "Kaş, in August.")
        #expect(pipeline.result(for: request) == enhanced, "kept for the next redraw")
    }
}

@Suite("Editorial: performance")
struct EditorialPerformanceTests {
    @Test func wordsAreCheapAndCachedWordsAreFree() {
        let pipeline = EditorialPipeline(capacity: 1_000)
        let clock = ContinuousClock()
        var requests: [EditorialRequest] = []
        for index in 0..<400 {
            var context = EditorialFixture.kas()
            context.counts.memories = 10 + index
            requests.append(EditorialRequest(context: context, kind: EditorialRequestKind.allCases[index % EditorialRequestKind.allCases.count]))
        }
        let cold = clock.measure { for request in requests { _ = pipeline.result(for: request) } }
        let warm = clock.measure { for request in requests { _ = pipeline.result(for: request) } }
        print("EDITORIAL_PERF requests=\(requests.count) cold=\(cold) warm=\(warm)")
        #expect(cold < .seconds(4), "\(cold)")
        #expect(warm < cold)
        #expect(pipeline.cacheStatistics.hits == requests.count)
    }
}
