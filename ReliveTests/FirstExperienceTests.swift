import ReliveCore
import XCTest
@testable import Relive

// First Experience V2 in the app: permission routing, bounded discovery, keeping only what the
// couple kept, cancellation, iCloud-only thumbnails, the start date, existing users, Premium.

/// A photo library whose access can change (like returning from Settings) and whose discovery
/// scan can be held open (to cancel it mid-way).
final class ConfigurablePhotoLibrary: PhotoLibraryProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var status: PhotoAccessStatus
    private var requestResult: PhotoAccessStatus
    private let library: [MemoryAsset]
    private var gate: CheckedContinuation<Void, Never>?
    private var holdsScan = false
    private(set) var scans = 0

    init(status: PhotoAccessStatus, requestResult: PhotoAccessStatus = .full, library: [MemoryAsset]) {
        self.status = status
        self.requestResult = requestResult
        self.library = library
    }

    func setStatus(_ new: PhotoAccessStatus) { lock.withLock { status = new } }
    func holdScan() { lock.withLock { holdsScan = true } }
    func releaseScan() {
        let pending = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            holdsScan = false
            defer { gate = nil }
            return gate
        }
        pending?.resume()
    }

    func accessStatus() -> PhotoAccessStatus { lock.withLock { status } }
    func requestAccess() async -> PhotoAccessStatus {
        lock.withLock {
            status = requestResult
            return status
        }
    }

    func assets(withIdentifiers identifiers: [AssetID]) async -> [MemoryAsset] {
        let wanted = Set(identifiers)
        return library.filter { wanted.contains($0.id) }
    }

    func allAccessibleAssets() async -> [MemoryAsset] { library }

    func availableIdentifiers(among identifiers: [AssetID]) async -> Set<AssetID> {
        Set(identifiers).intersection(library.map(\.id))
    }

    func discoveryAssets(limit: Int) async -> DiscoveryLibraryScan {
        let hold = lock.withLock { () -> Bool in
            scans += 1
            return holdsScan
        }
        if hold {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.withLock { gate = continuation }
            }
        }
        let newest = library.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        return DiscoveryLibraryScan(assets: Array(newest.prefix(limit)), libraryCount: library.count)
    }
}

/// Analyses only what it is asked to, counting; can pretend thumbnails are iCloud-only.
final class RepresentativeAnalyzer: AssetAnalyzing, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var analysed: [AssetID] = []
    let unavailable: Bool
    let faces: Int

    init(unavailable: Bool = false, faces: Int = 2) {
        self.unavailable = unavailable
        self.faces = faces
    }

    func analyze(_ asset: MemoryAsset) async -> AssetAnalysis {
        lock.withLock { analysed.append(asset.id) }
        if unavailable { return .unavailable() }
        return AssetAnalysis(faceCount: faces, sharpness: 0.5, aestheticScore: 0.6)
    }
}

@MainActor
enum FirstExperienceKit {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    static let home = GeoCoordinate(latitude: 41.04, longitude: 29.00)
    static let kas = GeoCoordinate(latitude: 36.20, longitude: 29.64)

    /// Everyday life at home for nine months, a four-day trip, two older evenings and a screenshot.
    static func library() -> [MemoryAsset] {
        var assets: [MemoryAsset] = []
        func burst(_ prefix: String, _ count: Int, _ start: Date, _ location: GeoCoordinate?) {
            for index in 0..<count {
                assets.append(MemoryAsset(
                    localIdentifier: "\(prefix)-\(index)",
                    creationDate: start.addingTimeInterval(Double(index) * 900),
                    location: location,
                    pixelWidth: 4032,
                    pixelHeight: 3024
                ))
            }
        }
        for month in 1...9 {
            burst("home-\(month)", 4, date(2026, month, 3, 19), home)
        }
        for day in 6...9 {
            burst("kas-\(day)", 6, date(2026, 8, day, 10), kas)
        }
        burst("before-a", 4, date(2019, 5, 2, 19), nil)
        burst("before-b", 4, date(2019, 9, 12, 19), nil)
        assets.append(MemoryAsset(localIdentifier: "screenshot", creationDate: date(2026, 8, 10), traits: [.screenshot], pixelWidth: 1170, pixelHeight: 2532))
        return assets
    }

    static func store(library: any PhotoLibraryProviding, analyzer: any AssetAnalyzing = InstantAnalyzer(), repository: InMemoryStoryRepository = InMemoryStoryRepository()) -> StoryStore {
        StoryStore(
            repository: repository,
            photoLibrary: library,
            analyzer: analyzer,
            placeResolver: NoPlaceLookups(),
            analytics: InMemoryAnalyticsTracker(),
            calendar: calendar
        )
    }

    static func waitUntil(_ model: DiscoveryModel, timeout: TimeInterval = 10, _ condition: (DiscoveryModel.Phase) -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(model.phase), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}

@MainActor
final class DiscoveryModelTests: XCTestCase {
    typealias K = FirstExperienceKit

    func testFullAccessFindsPossibleMomentsWithBoundedImageWork() async throws {
        let library = ConfigurablePhotoLibrary(status: .full, library: K.library())
        let analyzer = RepresentativeAnalyzer()
        let store = K.store(library: library, analyzer: analyzer)
        let analytics = InMemoryAnalyticsTracker()
        let model = DiscoveryModel(analytics: analytics)
        model.start(store: store, relationshipStart: nil)
        await K.waitUntil(model) { $0 == .ready || $0 == .nothingFound }
        XCTAssertEqual(model.phase, .ready)
        XCTAssertFalse(model.candidates.isEmpty)
        XCTAssertTrue(model.candidates.contains { $0.isTrip }, "the trip is a possible moment")
        // Only representatives were analysed: a few per moment, never the library.
        XCTAssertLessThanOrEqual(analyzer.analysed.count, DiscoveryConfiguration.standard.maximumAnalysedThumbnails)
        XCTAssertLessThan(analyzer.analysed.count, K.library().count)
        XCTAssertTrue(Set(analyzer.analysed).isSubset(of: Set(model.candidates.flatMap(\.representativeIDs) + model.candidates.flatMap(\.assetIDs))))
        XCTAssertFalse(model.candidates.flatMap(\.assetIDs).contains("screenshot"))
        // Nothing is imported until the couple keeps something.
        XCTAssertFalse(store.hasSelection)
        XCTAssertTrue(analytics.events.contains { $0.name == .discoveryCompleted })
        for event in analytics.events {
            for value in event.properties.values {
                XCTAssertFalse(value.contains("kas") || value.contains("home"), "no identifiers in analytics: \(value)")
            }
        }
    }

    func testOnlyKeptMomentsAreImportedAndTheRestIsForgotten() async throws {
        let library = ConfigurablePhotoLibrary(status: .full, library: K.library())
        let store = K.store(library: library, analyzer: RepresentativeAnalyzer())
        let model = DiscoveryModel()
        model.start(store: store, relationshipStart: nil)
        await K.waitUntil(model) { $0 == .ready }
        let kept = try XCTUnwrap(model.candidates.first)
        let rejected = model.candidates.dropFirst()
        model.decide(kept, .keep)
        for candidate in rejected { model.decide(candidate, .notOurs) }
        XCTAssertEqual(model.keptCount, 1)

        let imported = await model.importKept(into: store)
        XCTAssertEqual(imported, kept.assetCount)
        XCTAssertEqual(Set(store.assets.keys), Set(kept.assetIDs))
        XCTAssertTrue(Set(store.assets.keys).isDisjoint(with: Set(rejected.flatMap(\.assetIDs))), "rejected moments never enter the story")
        // Temporary discovery data is gone.
        XCTAssertTrue(model.candidates.isEmpty)
        XCTAssertEqual(model.keptCount, 0)
    }

    func testCancellingKeepsNothingAndOffersTheManualPath() async {
        let library = ConfigurablePhotoLibrary(status: .full, library: K.library())
        library.holdScan()
        let store = K.store(library: library)
        let analytics = InMemoryAnalyticsTracker()
        let model = DiscoveryModel(analytics: analytics)
        model.start(store: store, relationshipStart: nil)
        await K.waitUntil(model) { $0 == .scanning }
        XCTAssertEqual(model.phase, .scanning)
        model.cancel()
        library.releaseScan()
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(model.phase, .cancelled, "a finished scan never resurrects a cancelled discovery")
        XCTAssertTrue(model.candidates.isEmpty)
        XCTAssertFalse(store.hasSelection, "no half-imported story")
        XCTAssertTrue(analytics.events.contains { $0.name == .discoveryCancelled })
    }

    func testLimitedDeniedAndReturningFromSettings() async {
        // Apple's dialog: "Limit Access…" — the couple's own selection is the start.
        let limited = ConfigurablePhotoLibrary(status: .notDetermined, requestResult: .limited, library: K.library())
        let limitedModel = DiscoveryModel()
        limitedModel.start(store: K.store(library: limited), relationshipStart: nil)
        await K.waitUntil(limitedModel) { $0 == .limitedAccess }
        XCTAssertEqual(limitedModel.phase, .limitedAccess)
        XCTAssertEqual(limited.scans, 0, "no library scan without full access")

        // "Don't Allow": nothing is read; then access is granted in Settings and Relive looks again.
        let denied = ConfigurablePhotoLibrary(status: .notDetermined, requestResult: .denied, library: K.library())
        let store = K.store(library: denied)
        let model = DiscoveryModel()
        model.start(store: store, relationshipStart: nil)
        await K.waitUntil(model) { $0 == .denied }
        XCTAssertEqual(model.phase, .denied)
        XCTAssertEqual(denied.scans, 0)
        denied.setStatus(.full)
        model.start(store: store, relationshipStart: nil)
        await K.waitUntil(model) { $0 == .ready }
        XCTAssertEqual(model.phase, .ready)
    }

    func testICloudOnlyThumbnailsLeaveMetadataRanking() async {
        let library = ConfigurablePhotoLibrary(status: .full, library: K.library())
        let store = K.store(library: library, analyzer: RepresentativeAnalyzer(unavailable: true))
        let model = DiscoveryModel()
        model.start(store: store, relationshipStart: nil)
        await K.waitUntil(model) { $0 == .ready }
        XCTAssertEqual(model.phase, .ready, "moments are still suggested without local thumbnails")
        XCTAssertTrue(model.candidates.allSatisfy { $0.faces == .unknown && $0.score == $0.metadataScore })
    }

    func testTheRelationshipStartLimitsSuggestions() async {
        let library = ConfigurablePhotoLibrary(status: .full, library: K.library())
        let store = K.store(library: library, analyzer: RepresentativeAnalyzer())
        let model = DiscoveryModel()
        model.start(store: store, relationshipStart: K.date(2025, 1, 1))
        await K.waitUntil(model) { $0 == .ready }
        XCTAssertFalse(model.candidates.flatMap(\.assetIDs).contains { $0.hasPrefix("before-") })
        XCTAssertEqual(model.diagnostics?.excludedBeforeStart, 8)
    }
}

@MainActor
final class FirstExperienceRoutingTests: XCTestCase {
    typealias K = FirstExperienceKit

    func testANewCoupleSkipsTheDateAndChoosesHowToBegin() {
        let repository = InMemoryStoryRepository()
        let store = K.store(library: FakePhotoLibrary(assets: []), repository: repository)
        let app = AppModel(storyStore: store, repository: repository, analytics: InMemoryAnalyticsTracker())
        XCTAssertTrue(app.isOnboarding)
        XCTAssertEqual(app.onboardingStep, .welcome)
        app.beginOnboarding()
        app.setPartnerName("Emma")
        app.skipRelationshipStart()
        XCTAssertNil(app.relationship?.start, "the earliest photo is never taken as the start")
        XCTAssertTrue(repository.profile.relationshipStartSkipped)

        // A relaunch resumes at "How would you like to begin?", not at the date again.
        let relaunched = AppModel(storyStore: store, repository: repository, analytics: InMemoryAnalyticsTracker())
        XCTAssertEqual(relaunched.onboardingStep, .chooseStart)

        relaunched.chooseStartPath(.discovery)
        XCTAssertEqual(relaunched.onboardingStep, .discoveryPrivacy)
        relaunched.chooseStartPath(.manual)
        XCTAssertEqual(relaunched.onboardingStep, .photos)
        XCTAssertEqual(repository.profile.photoStartPath, "manual")
    }

    func testExistingCouplesNeverSeeOnboardingAgain() async {
        let repository = InMemoryStoryRepository(assets: Array(K.library().prefix(8)))
        let saved = RelationshipStart(date: K.date(2018, 3, 1), precision: .month)
        repository.profile.relationship = RelationshipProfile(partnerName: "Emma", start: saved)
        repository.profile.storyRevealedAt = K.date(2025, 1, 1)
        let store = K.store(library: FakePhotoLibrary(assets: K.library()), repository: repository)
        let app = AppModel(storyStore: store, repository: repository, analytics: InMemoryAnalyticsTracker())
        XCTAssertFalse(app.isOnboarding)
        XCTAssertEqual(app.relationship?.start, saved, "an existing couple's real date is unchanged")
        XCTAssertEqual(repository.profile.relationship?.start, saved)
        XCTAssertFalse(repository.profile.relationshipStartSkipped)
        XCTAssertEqual(store.relationshipStart, saved, "the story knows the couple's start")
    }

    func testTappingThroughOnboardingNeverCreatesAStartDate() {
        let repository = InMemoryStoryRepository()
        let store = K.store(library: FakePhotoLibrary(assets: []), repository: repository)
        let app = AppModel(storyStore: store, repository: repository, analytics: InMemoryAnalyticsTracker())
        app.beginOnboarding()
        app.setPartnerName("Emma")
        // The date screen's untouched draft has nothing to save.
        let untouched = RelationshipDateDraft()
        XCTAssertNil(untouched.start)
        XCTAssertFalse(untouched.isComplete, "Continue stays disabled")
        XCTAssertNil(app.relationship?.start)
        XCTAssertNil(repository.profile.relationship?.start, "no date is pre-saved")
        XCTAssertFalse(repository.profile.relationshipStartSkipped)
        XCTAssertNil(store.relationshipStart)
        // A relaunch asks again rather than assuming one.
        let relaunched = AppModel(storyStore: store, repository: repository, analytics: InMemoryAnalyticsTracker())
        XCTAssertEqual(relaunched.onboardingStep, .startDate)
    }

    func testAnExplicitlyChosenDateIsTheOneKept() throws {
        let repository = InMemoryStoryRepository()
        let store = K.store(library: FakePhotoLibrary(assets: []), repository: repository)
        let app = AppModel(storyStore: store, repository: repository, analytics: InMemoryAnalyticsTracker())
        app.beginOnboarding()
        app.setPartnerName("Emma")
        var draft = RelationshipDateDraft()
        draft.month = 3
        draft.year = 2021
        let chosen = try XCTUnwrap(draft.start)
        app.setRelationshipStart(chosen)
        XCTAssertEqual(chosen.precision, .month)
        XCTAssertEqual(Calendar.current.dateComponents([.year, .month, .day], from: chosen.date), DateComponents(year: 2021, month: 3, day: 1))
        XCTAssertEqual(repository.profile.relationship?.start, chosen)
        XCTAssertFalse(repository.profile.relationshipStartSkipped)
        let relaunched = AppModel(storyStore: store, repository: repository, analytics: InMemoryAnalyticsTracker())
        XCTAssertEqual(relaunched.relationship?.start, chosen)
        XCTAssertEqual(relaunched.onboardingStep, .chooseStart)
    }

    func testSkipKeepsTheStartUnknownAndMakesNoDurationClaims() async {
        let assets = K.library().filter { $0.id.hasPrefix("before-") || $0.id.hasPrefix("home-") }
        let repository = InMemoryStoryRepository()
        let store = K.store(library: FakePhotoLibrary(assets: assets), repository: repository)
        let app = AppModel(storyStore: store, repository: repository, analytics: InMemoryAnalyticsTracker())
        app.beginOnboarding()
        app.setPartnerName("Emma")
        app.skipRelationshipStart()
        await store.importSelection(identifiers: assets.map(\.id))
        await store.process()

        let relaunched = AppModel(storyStore: store, repository: repository, analytics: InMemoryAnalyticsTracker())
        XCTAssertNil(relaunched.relationship?.start, "skip persists the unknown state")
        XCTAssertTrue(repository.profile.relationshipStartSkipped)
        XCTAssertNil(store.relationshipStart)
        // No invented boundary: nothing is set apart as "before", nothing counts days together.
        XCTAssertFalse(store.sections.contains { $0.id == TimelineBuilder.beforeStartID })
        XCTAssertNotNil(store.firstMemoryDate, "the timeline is organised by its first memory only")
    }
}

@MainActor
final class RelationshipDateDraftTests: XCTestCase {
    func testNothingIsSelectedUntilChosen() {
        var draft = RelationshipDateDraft()
        XCTAssertNil(draft.month)
        XCTAssertNil(draft.year)
        XCTAssertNil(draft.start)
        draft.month = 8
        XCTAssertNil(draft.start, "a month alone is not a date")
        draft.year = 2024
        XCTAssertEqual(draft.start?.precision, .month)
    }

    func testAnExactDayCountsOnlyOnceTapped() {
        var draft = RelationshipDateDraft()
        draft.knowsExactDay = true
        XCTAssertNil(draft.start, "the calendar's displayed day is not a choice")
        draft.exactDate = Date(timeIntervalSince1970: 1_600_000_000)
        draft.exactDayChosen = true
        XCTAssertEqual(draft.start?.precision, .day)
        XCTAssertEqual(draft.start?.date, Date(timeIntervalSince1970: 1_600_000_000))
    }

    func testASavedDateReopensAsChosen() {
        let saved = RelationshipStart(date: Date(timeIntervalSince1970: 1_600_000_000), precision: .day)
        XCTAssertEqual(RelationshipDateDraft(start: saved).start, saved)
        let month = RelationshipStart(date: Date(timeIntervalSince1970: 1_600_000_000), precision: .month)
        XCTAssertEqual(RelationshipDateDraft(start: month).start?.precision, .month)
    }

    func testAFutureChoiceIsNeverInTheFuture() {
        var draft = RelationshipDateDraft()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        draft.month = 12
        draft.year = 2099
        XCTAssertLessThanOrEqual(draft.makeStart(now: now)?.date ?? .distantFuture, now)
    }
}

@MainActor
final class FirstExperienceCompletionTests: XCTestCase {
    typealias K = FirstExperienceKit

    func testFinishingOnboardingOpensStoryAndTheChosenMoment() {
        let repository = InMemoryStoryRepository()
        let store = K.store(library: FakePhotoLibrary(assets: []), repository: repository)
        let app = AppModel(storyStore: store, repository: repository, analytics: InMemoryAnalyticsTracker())
        let moment = MomentID()
        app.completeOnboarding(result: "moment")
        app.pendingMomentID = moment
        XCTAssertFalse(app.isOnboarding)
        XCTAssertEqual(app.selectedTab, .story)
        XCTAssertNotNil(repository.profile.storyRevealedAt)
        XCTAssertEqual(app.pendingMomentID, moment)
    }
}

@MainActor
final class RelationshipStartStoryTests: XCTestCase {
    typealias K = FirstExperienceKit

    func testMemoriesBeforeTheStartAreShownApartAndNeverDeleted() async {
        let assets = K.library().filter { $0.id.hasPrefix("before-") || $0.id.hasPrefix("home-") }
        let repository = InMemoryStoryRepository()
        let store = K.store(library: FakePhotoLibrary(assets: assets), repository: repository)
        await store.importSelection(identifiers: assets.map(\.id))
        await store.process()
        let total = store.visibleMoments.count

        store.relationshipStart = RelationshipStart(date: K.date(2025, 6, 1), precision: .month)
        XCTAssertEqual(store.sections.first?.id, TimelineBuilder.beforeStartID)
        XCTAssertTrue(store.sections.first?.title.hasPrefix("Before ") ?? false)
        XCTAssertEqual(store.visibleMoments.count, total, "kept memories from before are still there")
        let after = store.sections.filter { $0.id != TimelineBuilder.beforeStartID }.flatMap(\.items).flatMap(\.moments)
        XCTAssertTrue(after.allSatisfy { ($0.startDate ?? .distantFuture) >= K.date(2025, 6, 1, 0) })

        store.relationshipStart = nil
        XCTAssertFalse(store.sections.contains { $0.id == TimelineBuilder.beforeStartID }, "no start date, nothing is set apart")
        XCTAssertNotNil(store.firstMemoryDate)
    }
}

@MainActor
final class FirstSessionPremiumTests: XCTestCase {
    func testTheFirstDiscoveryRecapIsShownInFullOnlyThatOnce() {
        let first = RecapRequest(period: .month(MonthKey(year: 2026, month: 8)), origin: RecapRequest.firstDiscoveryOrigin)
        XCTAssertTrue(first.isFirstDiscovery)
        for origin in ["made_for_you", "made_for_you_today", "monthly_recap", "recap_list"] {
            XCTAssertFalse(RecapRequest(period: .month(MonthKey(year: 2026, month: 8)), origin: origin).isFirstDiscovery)
        }
    }

    func testPremiumRulesAreUnchanged() async {
        let premium = PremiumTestKit.store()
        await premium.refreshEntitlements()
        XCTAssertTrue(premium.allowance.isAvailable, "the one free creation is untouched")
        XCTAssertFalse(premium.hasAccess(to: .fullMonthlyRecap))
        XCTAssertFalse(premium.hasAccess(to: .memoryMovie))
        let gate = PremiumGate()
        var kept = false
        await gate.export(.memoryMovie, entry: .memoryMovie, premium: premium) { _ in kept = true }
        XCTAssertFalse(kept, "keeping a movie is still Premium")
    }

    func testAMovieCanBePreviewedWithoutPremium() {
        let (store, _) = CreationTestLibrary.makeStore()
        let model = MovieEditorModel(source: .photos(MovieTestKit.photos), library: store.creationLibrary, editorial: EditorialService(model: nil))
        XCTAssertTrue(model.plan.isReady, "the preview needs no purchase")
        XCTAssertFalse(model.plan.scenes.isEmpty)
    }
}
