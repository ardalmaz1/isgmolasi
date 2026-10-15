import Foundation
import Testing
@testable import ReliveCore

/// The Kaş context used throughout: a four-day trip, August 6–9, 2026, 31 memories, two places.
enum EditorialFixture {
    static func kas(surface: EditorialSurface = .madeForYou, language: EditorialLanguage = .english, places: [String] = ["Kaş"], trip: String? = "Kaş") -> EditorialContext {
        EditorialContext(
            surface: surface,
            language: language,
            firstDay: DayKey(year: 2026, month: 8, day: 6),
            lastDay: DayKey(year: 2026, month: 8, day: 9),
            months: [MonthKey(year: 2026, month: 8)],
            places: places,
            tripName: trip,
            counts: .init(memories: 31, moments: 3, places: places.count),
            periodLabel: "August 6–9, 2026",
            factualTitle: "Kaş · August 6–9, 2026"
        )
    }

    static func accepts(_ text: String, _ context: EditorialContext, kind: EditorialRequestKind = .title, authorship: EditorialAuthorship = .relive) -> Bool {
        EditorialValidator().accepts(EditorialCandidate(text: text, provider: "fake", authorship: authorship), request: EditorialRequest(context: context, kind: kind))
    }

    static func rejections(_ text: String, _ context: EditorialContext) -> [EditorialRejection] {
        EditorialValidator().rejections(for: EditorialCandidate(text: text, provider: "fake"), request: EditorialRequest(context: context, kind: .title))
    }
}

@Suite("Editorial: the safety matrix")
struct EditorialSafetyTests {
    typealias E = EditorialFixture

    @Test func theSpecMatrix() {
        let kas = E.kas()
        #expect(!E.accepts("The happiest four days of your life.", kas))
        #expect(E.rejections("32 memories in Kaş.", kas).contains(.unsupportedNumber))
        #expect(E.rejections("Four days in Antalya.", kas).contains(.unsupportedPlace))
        #expect(E.rejections("You and Kübra in Kaş.", kas).contains(.identityClaim))
        #expect(E.accepts("Four days in Kaş.", kas))
        #expect(E.accepts("Kaş · August 2026", kas))
        #expect(!E.accepts("The trip you'll never forget.", kas))
        #expect(E.rejections("Your favorite trip.", kas).contains(.ranking))
    }

    @Test func numbersMustBeInTheFacts() {
        let kas = E.kas()
        #expect(E.accepts("31 memories from Kaş.", kas))
        #expect(E.accepts("Four days, 31 memories.", kas))
        #expect(!E.accepts("30 memories from Kaş.", kas))
        #expect(!E.accepts("Six days in Kaş.", kas))
        #expect(!E.accepts("Three moments, 12 places.", kas))
    }

    @Test func datesMustBeInTheFacts() {
        let kas = E.kas()
        #expect(E.accepts("Four days in August.", kas))
        #expect(E.accepts("Kaş · August 6–9", kas))
        #expect(E.rejections("Five days in August.", kas).contains(.unsupportedNumber))
        #expect(E.rejections("July 2026", kas).contains(.unsupportedDate))
        #expect(E.rejections("August 10", kas).contains(.unsupportedNumber))
        #expect(E.rejections("A Saturday in Kaş.", kas).contains(.unsupportedDate))
    }

    @Test func placesMustBeInTheFacts() {
        let two = E.kas(places: ["Kaş", "Fethiye"], trip: "Lycian Coast")
        #expect(E.accepts("Kaş, in August.", two))
        #expect(E.accepts("From Kaş to Fethiye", two))
        #expect(!E.accepts("Antalya nights.", two))
        #expect(!E.accepts("Four days in Antalya.", two), "no broader geography Relive doesn't already show")
    }

    @Test func feelingsAndRankingsAreNeverRelivesWords() {
        let kas = E.kas()
        let refused = [
            "The trip that changed everything.", "The happiest four days of your year.", "Where you fell in love all over again.",
            "Your favorite place.", "Most romantic days in Kaş.", "Unforgettable Kaş.", "A perfect August.", "Special days in Kaş.",
            "A life-changing trip.", "Deeply in love in Kaş.", "The adventure of a lifetime.", "Your best days in Kaş.",
            "A beautiful relationship.", "Top memories from Kaş.",
        ]
        for text in refused { #expect(!E.accepts(text, kas), "\(text)") }
    }

    @Test func warmButFactualWordingIsAllowed() {
        let kas = E.kas()
        let bergama = EditorialContext(surface: .recap, months: [MonthKey(year: 2026, month: 9)], places: ["Bergama"], counts: .init(memories: 12, frames: 9))
        let autumn = EditorialContext(surface: .ourYear, months: [8, 9, 10].map { MonthKey(year: 2026, month: $0) }, counts: .init(memories: 40))
        #expect(E.accepts("A few days in Kaş.", kas))
        #expect(E.accepts("August, together.", kas))
        #expect(E.accepts("Back in Bergama.", bergama))
        #expect(E.accepts("The month began here.", bergama))
        #expect(E.accepts("September in 9 frames.", bergama))
        #expect(E.accepts("September in frames.", bergama))
        #expect(E.accepts("From August to October.", autumn))
        #expect(E.accepts("Your year, month by month.", autumn))
    }

    @Test func noFactsNoClaims() {
        let unknown = EditorialContext(surface: .story, counts: .init(memories: 8))
        #expect(E.rejections("Four days in Kaş.", unknown).contains(.unsupportedPlace), "no location: none created")
        #expect(E.rejections("August memories", unknown).contains(.unsupportedDate), "no date: none created")
        #expect(E.rejections("Summer memories", unknown).contains(.unsupportedSeason), "no season: none mentioned")
        #expect(E.rejections("A trip to remember", unknown).contains(.unsupportedTrip), "no trip: not called one")
        #expect(E.rejections("You and Emma.", unknown).contains(.identityClaim), "faces are never identities")
        #expect(E.rejections("Sunset over the sea.", unknown).contains(.visualClaim), "no picture contents without visual facts")
        #expect(E.rejections("Their anniversary.", unknown).contains(.relationshipEvent))
    }

    @Test func mixedYearsNeverLeak() {
        let kas2026 = E.kas()
        #expect(!E.accepts("Kaş · August 2025", kas2026))
        #expect(!E.accepts("Since 2025", kas2026))
    }
}

@Suite("Editorial: user words are the user's")
struct EditorialUserTextTests {
    typealias E = EditorialFixture

    @Test func theUsersOwnWordsStandAsTheyAre() {
        let kas = E.kas()
        #expect(E.accepts("Our favorite trip.", kas, authorship: .user))
        #expect(E.accepts("Our happiest summer", kas, authorship: .user))
        #expect(!E.accepts("Our favorite trip.", kas), "Relive can't say it on its own")
        // When the user wrote it, Relive may repeat it verbatim.
        var withUserTitle = kas
        withUserTitle.userText = "Our favorite trip"
        #expect(E.accepts("Our favorite trip · August 2026", withUserTitle))
    }
}

@Suite("Editorial: Turkish")
struct EditorialTurkishTests {
    typealias E = EditorialFixture

    @Test func turkishWordingFollowsTheSameRules() {
        let kas = E.kas(language: .turkish)
        let september = EditorialContext(surface: .recap, language: .turkish, months: [MonthKey(year: 2026, month: 9)], counts: .init(frames: 9))
        #expect(E.accepts("Kaş'ta dört gün.", kas))
        #expect(E.accepts("Ağustos, birlikte.", kas))
        #expect(E.accepts("Eylül'den 9 kare.", september))
        #expect(!E.accepts("En mutlu tatiliniz.", kas))
        #expect(!E.accepts("En romantik anınız.", kas))
        #expect(!E.accepts("Unutulmaz dört gün.", kas))
        #expect(!E.accepts("Kaş'ta beş gün.", kas), "five days isn't true")
        #expect(!E.accepts("Temmuz 2026", kas))
        #expect(!E.accepts("Antalya'da dört gün.", kas))
        #expect(E.accepts("En mutlu yazımız", kas, authorship: .user), "the user's own words")
    }

    @Test func turkishSuffixesFollowVowelHarmony() {
        #expect(TurkishSuffix.locative("Kaş") == "'ta")
        #expect(TurkishSuffix.locative("Bergama") == "'da")
        #expect(TurkishSuffix.locative("Fethiye") == "'de")
        #expect(TurkishSuffix.ablative("Eylül") == "'den")
        #expect(TurkishSuffix.dative("Ekim") == "'e")
    }

    @Test func theWriterSpeaksTurkishFromTheSameFacts() {
        let result = EditorialPipeline().result(for: EditorialRequest(context: E.kas(language: .turkish), kind: .title))
        #expect(result.variants.contains("Kaş'ta dört gün."))
        #expect(result.variants.allSatisfy { E.accepts($0, E.kas(language: .turkish)) })
    }
}

@Suite("Editorial: writer, pipeline and router")
struct EditorialPipelineTests {
    typealias E = EditorialFixture

    struct FakeModel: EditorialModelProviding {
        var name = "fake"
        var available = true
        var replies: [String] = []
        var fails = false
        func isAvailable() async -> Bool { available }
        func candidates(for request: EditorialRequest) async throws -> [String] {
            if fails { throw CancellationError() }
            return replies
        }
    }

    @Test func madeForYouLeadsWithTheEditorialTitle() {
        let result = EditorialPipeline().result(for: EditorialRequest(context: E.kas(), kind: .title))
        #expect(result.text == "Four days in Kaş.")
        #expect(result.variants.count >= 2 && result.variants.count <= EditorialPipeline.maximumVariants)
        #expect(result.variants.contains("Kaş · August 2026"))
        #expect(!result.usedFallback)
        let subtitle = EditorialPipeline().result(for: EditorialRequest(context: E.kas(), kind: .subtitle))
        #expect(subtitle.text == "31 memories · 4 days · August 6–9, 2026")
    }

    @Test func surfacesWithATitleKeepItFirst() {
        for surface in [EditorialSurface.movie, .book, .story, .collage] {
            let result = EditorialPipeline().result(for: EditorialRequest(context: E.kas(surface: surface), kind: .title))
            if surface == .movie || surface == .collage {
                // The factual title is longer than these surfaces allow: the next safe variant leads.
                #expect(result.text == "Four days in Kaş." || result.text == "Kaş · August 6–9, 2026", "\(surface): \(result.text)")
            } else {
                #expect(result.text == "Kaş · August 6–9, 2026", "\(surface)")
            }
        }
    }

    @Test func everySurfaceAgreesWithTheSameFacts() {
        for surface in EditorialSurface.allCases {
            for kind in EditorialRequestKind.allCases {
                let context = E.kas(surface: surface)
                let result = EditorialPipeline().result(for: EditorialRequest(context: context, kind: kind))
                for variant in result.variants {
                    #expect(E.accepts(variant, context, kind: kind), "\(surface) \(kind): \(variant)")
                    #expect(!variant.contains("August 5") && !variant.contains("10"), "no surface changes the dates")
                }
            }
        }
    }

    @Test func noFactsMeansTheFactualTitle() {
        let bare = EditorialContext(surface: .collage, factualTitle: "Our Memories")
        let result = EditorialPipeline().result(for: EditorialRequest(context: bare, kind: .title))
        #expect(result.text == "Our Memories")
    }

    @Test func resultsAreCachedByFactsNotScreens() {
        let pipeline = EditorialPipeline()
        let request = EditorialRequest(context: E.kas(), kind: .title)
        _ = pipeline.result(for: request)
        _ = pipeline.result(for: request)
        #expect(pipeline.cacheStatistics.hits == 1 && pipeline.cacheStatistics.misses == 1)
        var changed = E.kas()
        changed.counts.memories = 30
        _ = pipeline.result(for: EditorialRequest(context: changed, kind: .title))
        #expect(pipeline.cacheStatistics.misses == 2, "changed facts are a different request")
    }

    @Test func aModelOnlyAddsValidatedAlternatives() async {
        let request = EditorialRequest(context: E.kas(), kind: .title)
        let model = FakeModel(replies: ["Kaş, in August.", "The happiest days of your life.", "Five days in Kaş.", "You and Kübra in Kaş."])
        let result = await EditorialRouter(pipeline: EditorialPipeline(), model: model).enhanced(request)
        #expect(result.text == "Four days in Kaş.", "the first words never change")
        #expect(result.variants.contains("Kaş, in August."))
        #expect(!result.variants.contains { $0.contains("happiest") || $0.contains("Five") || $0.contains("Kübra") })
        #expect(result.rejections.contains(.emotionalClaim) || result.rejections.contains(.ranking))
        #expect(result.rejections.contains(.unsupportedNumber))
        #expect(result.rejections.contains(.identityClaim))
    }

    @Test func unavailableOrFailingModelsFallBackSilently() async {
        let request = EditorialRequest(context: E.kas(), kind: .title)
        let base = EditorialPipeline().result(for: request)
        let unavailable = await EditorialRouter(pipeline: EditorialPipeline(), model: FakeModel(available: false, replies: ["Kaş, in August."])).enhanced(request)
        #expect(unavailable == base)
        let failing = await EditorialRouter(pipeline: EditorialPipeline(), model: FakeModel(fails: true)).enhanced(request)
        #expect(failing == base)
        let none = await EditorialRouter(pipeline: EditorialPipeline()).enhanced(request)
        #expect(none == base)
    }

    @Test func factsAreClassifiedAndNeverInterpreted() {
        let facts = E.kas().facts
        #expect(facts.contains { $0.factClass == .verified && $0.key == "place" && $0.value == "Kaş" })
        #expect(facts.contains { $0.factClass == .derived && $0.key == "dayCount" && $0.value == "4" })
        #expect(!facts.contains { $0.factClass == .interpretation })
        let json = String(data: (try? JSONEncoder().encode(E.kas())) ?? Data(), encoding: .utf8) ?? ""
        #expect(!json.contains("latitude") && !json.contains("assetID"), "no coordinates or identifiers in a context")
    }

    @Test func recapTextGoesThroughTheSameValidator() {
        let facts = EditorialFacts.trip(name: "Kaş", days: 4, memories: 31, dateLabel: "August 6–9")
        #expect(ValidatedEditorialTextProvider.isAcceptable(EditorialText(eyebrow: "A trip", title: "Four days in Kaş."), for: facts))
        #expect(!ValidatedEditorialTextProvider.isAcceptable(EditorialText(title: "Four days in Antalya."), for: facts))
        #expect(!ValidatedEditorialTextProvider.isAcceptable(EditorialText(title: "Your favorite trip."), for: facts))
    }
}
