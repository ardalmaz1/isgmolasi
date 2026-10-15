import ReliveCore
import XCTest
@testable import Relive

// Editorial intelligence in the app: which provider writes, what happens when it can't, the
// movie title the user controls (and keeps in the draft), local analytics without text, Premium
// unchanged, and no network.

/// A stand-in on-device model (no Apple model in tests).
struct FakeEditorialModel: EditorialModelProviding {
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

/// Counts every URL request made through the shared URL loading system while installed.
final class NetworkCounter: URLProtocol {
    nonisolated(unsafe) static var count = 0
    override class func canInit(with request: URLRequest) -> Bool {
        count += 1
        return false
    }
}

enum EditorialTestKit {
    static func kasRequest(_ kind: EditorialRequestKind = .title, surface: EditorialSurface = .movie) -> EditorialRequest {
        EditorialRequest(
            context: EditorialContext(
                surface: surface,
                firstDay: DayKey(year: 2026, month: 8, day: 6),
                lastDay: DayKey(year: 2026, month: 8, day: 9),
                months: [MonthKey(year: 2026, month: 8)],
                places: ["Kaş"],
                tripName: "Kaş",
                counts: EditorialContext.Counts(memories: 31, moments: 3),
                periodLabel: "August 6–9, 2026",
                factualTitle: "Kaş"
            ),
            kind: kind
        )
    }
}

final class EditorialProviderTests: XCTestCase {
    func testTheAppleOnDeviceModelIsTheOnlyModelAndTestsCanSwitchItOff() {
        XCTAssertEqual(EditorialService.model(for: [])?.name, "apple-on-device")
        XCTAssertNil(EditorialService.model(for: ["-ReliveEditorialModelOff"]))
        XCTAssertEqual(EditorialService(model: nil).providerName, "deterministic")
    }

    func testWhereTheOnDeviceModelCantRunRelivesWordsAreUsedSilently() async {
        let provider = AppleOnDeviceEditorialProvider()
        let available = await provider.isAvailable()
        print("EDITORIAL_PROVIDER name=\(provider.name) available=\(available) status=\(provider.availabilityCode())")
        let request = EditorialTestKit.kasRequest(.subtitle)
        let pipeline = EditorialPipeline()
        let base = pipeline.result(for: request)
        let enhanced = await EditorialRouter(pipeline: pipeline, model: provider).enhanced(request)
        XCTAssertEqual(enhanced.text, base.text, "what is shown never depends on the model")
        if !available {
            XCTAssertEqual(enhanced, base, "unavailable: Relive's own words, nothing else")
        }
        for text in enhanced.variants {
            XCTAssertTrue(EditorialValidator().accepts(EditorialCandidate(text: text, provider: "check"), request: request), text)
        }
    }

    func testAFailingOrUntruthfulModelNeverReachesTheScreen() async {
        let request = EditorialTestKit.kasRequest()
        let failing = EditorialService(pipeline: EditorialPipeline(), model: FakeEditorialModel(fails: true))
        let changed = await failing.enhance(request)
        XCTAssertFalse(changed)
        let liar = EditorialService(pipeline: EditorialPipeline(), model: FakeEditorialModel(replies: ["Our honeymoon in Kaş.", "Six days at the beach.", "Kübra and Emma in Kaş."]))
        let lied = await liar.enhance(request)
        XCTAssertFalse(lied, "every invented fact is refused")
        let honest = EditorialService(pipeline: EditorialPipeline(), model: FakeEditorialModel(replies: ["Kaş, in August."]))
        let added = await honest.enhance(request)
        XCTAssertTrue(added)
        XCTAssertEqual(honest.router.immediate(request).variants[1], "Kaş, in August.")
    }

    func testNoNetworkIsUsed() async {
        URLProtocol.registerClass(NetworkCounter.self)
        defer { URLProtocol.unregisterClass(NetworkCounter.self) }
        NetworkCounter.count = 0
        let service = EditorialService(pipeline: EditorialPipeline(), model: AppleOnDeviceEditorialProvider())
        for kind in EditorialRequestKind.allCases {
            _ = await service.enhance(EditorialTestKit.kasRequest(kind, surface: .recap))
        }
        XCTAssertEqual(NetworkCounter.count, 0, "editorial intelligence never touches the network")
    }
}

@MainActor
final class EditorialMovieTitleTests: XCTestCase {
    func testTryAnotherEditRemoveAndResetNeverChangeThePhotos() throws {
        let (store, _) = CreationTestLibrary.makeStore()
        let analytics = InMemoryAnalyticsTracker()
        let model = MovieEditorModel(source: .photos(MovieTestKit.photos), library: store.creationLibrary, analytics: analytics, editorial: EditorialService(model: nil))
        let photos = model.plan.photoIDs
        let first = try XCTUnwrap(model.openingTitle)
        XCTAssertFalse(model.plan.titleVariants.isEmpty)
        XCTAssertLessThanOrEqual(model.plan.titleVariants.count, 3)
        print("EDITORIAL_MOVIE variants=\(model.plan.titleVariants.count)")

        if model.canTryAnotherTitle {
            model.tryAnotherTitle()
            XCTAssertNotEqual(model.openingTitle, first)
            XCTAssertEqual(model.plan.scenes.first?.text?.title, model.openingTitle)
        }
        model.setOwnTitle("  Our favorite weekend ")
        XCTAssertEqual(model.openingTitle, "Our favorite weekend", "the user's words, as written")
        XCTAssertEqual(model.plan.openingTitleAuthorship, .user)
        model.removeTitle()
        XCTAssertNil(model.openingTitle)
        model.resetTitle()
        XCTAssertEqual(model.openingTitle, first)
        XCTAssertEqual(model.plan.photoIDs, photos, "words never change the photos")

        let editorialEvents = analytics.events.filter { $0.name.rawValue.hasPrefix("editorial_") }
        XCTAssertTrue(editorialEvents.contains { $0.name == .editorialUserEdited })
        for event in editorialEvents {
            for value in event.properties.values {
                XCTAssertFalse(value.contains("favorite") || value.contains("weekend") || value == first, "no text in analytics: \(value)")
            }
        }
    }

    func testTheUsersTitleSurvivesARelaunch() throws {
        let (store, repository) = CollectionTestStore.make()
        let model = MovieEditorModel(source: .photos(MovieTestKit.photos), library: store.creationLibrary, store: store, editorial: EditorialService(model: nil))
        model.setOwnTitle("Bizim yazımız")
        model.flush()
        let draft = try XCTUnwrap(store.drafts.first { $0.kind == .movie })
        XCTAssertEqual(draft.movie?.settings.titleChoice?.userText, "Bizim yazımız")

        let reopened = CollectionTestStore.reopen(repository)
        let saved = try XCTUnwrap(reopened.creation(id: draft.id))
        let restored = MovieEditorModel(restoring: saved, state: try XCTUnwrap(saved.movie), library: reopened.creationLibrary(for: saved), store: reopened, editorial: EditorialService(model: nil))
        XCTAssertEqual(restored.openingTitle, "Bizim yazımız")
        XCTAssertEqual(restored.plan.scenes.first?.text?.title, "Bizim yazımız")

        // Make it for me makes a new cut, but the user's words stay.
        restored.makeItForMe()
        XCTAssertEqual(restored.openingTitle, "Bizim yazımız")
    }

    func testAModelsAlternativeIsOfferedWithoutChangingWhatIsShown() async throws {
        let (store, _) = CreationTestLibrary.makeStore()
        let pipeline = EditorialPipeline.shared
        pipeline.clear()
        defer { pipeline.clear() }
        let first = MovieEditorModel(source: .photos(MovieTestKit.photos), library: store.creationLibrary, editorial: EditorialService(model: nil))
        let factual = try XCTUnwrap(first.plan.titleVariants.first)
        // A fake model that only repeats a known fact differently.
        let model = MovieEditorModel(source: .photos(MovieTestKit.photos), library: store.creationLibrary, editorial: EditorialService(model: FakeEditorialModel(replies: ["\(factual), again.", "The best days ever."])))
        XCTAssertEqual(model.openingTitle, factual)
        for _ in 0..<50 where !model.plan.titleVariants.contains("\(factual), again.") {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(model.openingTitle, factual, "the first words never jump")
        XCTAssertTrue(model.plan.titleVariants.contains("\(factual), again."))
        XCTAssertFalse(model.plan.titleVariants.contains { $0.contains("best") })
    }
}

@MainActor
final class EditorialPremiumTests: XCTestCase {
    func testEditorialChangesNothingAboutPremium() async {
        let premium = PremiumTestKit.store()
        await premium.refreshEntitlements()
        XCTAssertTrue(premium.allowance.isAvailable, "the free creation is untouched")
        let gate = PremiumGate()
        var exported = false
        await gate.export(.memoryMovie, entry: .memoryMovie, premium: premium) { _ in exported = true }
        XCTAssertFalse(exported, "a movie is still kept with Premium, words or not")
        XCTAssertEqual(PaywallCopy(entry: .memoryMovie).context, "Keep this movie")
        XCTAssertFalse(PaywallEntryPoint.allCases.contains { $0.rawValue.contains("editorial") }, "no AI tier, no editorial paywall")
    }
}
