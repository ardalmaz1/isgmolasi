import ReliveCore
import XCTest
@testable import Relive

// Commercial v1, through the real PremiumStore, PremiumGate and ExportController with a fake
// App Store (no live purchases, no PhotoKit).

@MainActor
enum PremiumTestKit {
    static func defaults() -> UserDefaults {
        let name = "relive-premium-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    static func store(
        _ client: FakeStoreKitClient = FakeStoreKitClient(),
        defaults: UserDefaults = defaults(),
        analytics: InMemoryAnalyticsTracker = InMemoryAnalyticsTracker()
    ) -> PremiumStore {
        PremiumStore(client: client, defaults: defaults, analytics: analytics)
    }

    /// Waits for something that happens asynchronously (a transaction update).
    static func wait(_ condition: @MainActor () -> Bool, timeout: TimeInterval = 3) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { throw ConditionTimedOut() }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

private enum ExportFailure: Error { case failed }

/// A saver that fails, like a full disk or denied access.
private struct FailingSaver: CreationSaving {
    func save(_ jpegs: [Data]) async throws -> [AssetID] { throw CreationExportError.saveFailed }
}

@MainActor
final class EntitlementStoreTests: XCTestCase {
    func testVerifiedActiveSubscriptionIsPremium() async {
        let client = FakeStoreKitClient()
        client.snapshot.transactions = [client.activeTransaction(.annual)]
        let premium = PremiumTestKit.store(client)
        XCTAssertEqual(premium.status, .unknown)
        await premium.refreshEntitlements()
        XCTAssertTrue(premium.isPremium)
        XCTAssertEqual(premium.status.grant?.role, .annual)
    }

    func testUnverifiedExpiredAndRevokedNeverGrantPremium() async {
        let client = FakeStoreKitClient()
        let premium = PremiumTestKit.store(client)

        client.snapshot.transactions = [client.activeTransaction(.annual, verified: false)]
        await premium.refreshEntitlements()
        XCTAssertFalse(premium.isPremium)
        XCTAssertEqual(premium.status, .free(.verificationFailed))

        var expired = client.activeTransaction(.monthly)
        expired.expirationDate = Date().addingTimeInterval(-60)
        client.snapshot.transactions = [expired]
        await premium.refreshEntitlements()
        XCTAssertEqual(premium.status, .free(.expired))

        var revoked = client.activeTransaction(.annual)
        revoked.revocationDate = Date()
        client.snapshot.transactions = [revoked]
        await premium.refreshEntitlements()
        XCTAssertEqual(premium.status, .free(.revoked))
    }

    func testPurchaseTurnsPremiumOnAndIsTracked() async {
        let analytics = InMemoryAnalyticsTracker()
        let client = FakeStoreKitClient()
        let premium = PremiumTestKit.store(client, analytics: analytics)
        await premium.loadProducts()
        XCTAssertEqual(premium.productsState, .loaded)
        XCTAssertEqual(premium.products.map(\.role), [.annual, .monthly], "annual first")

        let purchased = await premium.purchase(.annual, entry: .memoryBook)
        XCTAssertTrue(purchased)
        XCTAssertTrue(premium.isPremium)
        XCTAssertEqual(premium.purchaseState, .idle)
        let names = analytics.events.map(\.name)
        XCTAssertEqual(names, [.premiumPurchaseStarted, .premiumPurchaseCompleted])
        XCTAssertEqual(analytics.events.last?.properties, ["entry": "memory_book", "product": "annual"])
    }

    func testCancelledPendingAndUnverifiedPurchases() async {
        let client = FakeStoreKitClient()
        let premium = PremiumTestKit.store(client)
        await premium.loadProducts()

        client.purchaseOutcome = .cancelled
        let cancelled = await premium.purchase(.monthly, entry: .collageExport)
        XCTAssertFalse(cancelled)
        XCTAssertEqual(premium.purchaseState, .idle, "cancelling is not an error")
        XCTAssertFalse(premium.isPremium)

        client.purchaseOutcome = .pending
        let pending = await premium.purchase(.annual, entry: .collageExport)
        XCTAssertFalse(pending)
        XCTAssertEqual(premium.purchaseState, .pending)
        XCTAssertFalse(premium.isPremium)

        client.purchaseOutcome = .unverified
        let unverified = await premium.purchase(.annual, entry: .collageExport)
        XCTAssertFalse(unverified)
        XCTAssertFalse(premium.isPremium)
        guard case .failed = premium.purchaseState else { return XCTFail("an unverified purchase must not succeed") }

        client.purchaseFailure = .network
        let offline = await premium.purchase(.annual, entry: .collageExport)
        XCTAssertFalse(offline)
        XCTAssertEqual(premium.purchaseState, .failed(StoreFailure.network.message))
    }

    func testProductLoadFailureShowsRetryNotFakePrices() async {
        let client = FakeStoreKitClient()
        client.productFailure = .network
        let premium = PremiumTestKit.store(client)
        await premium.loadProducts()
        XCTAssertEqual(premium.productsState, .failed(StoreFailure.network.message))
        XCTAssertTrue(premium.products.isEmpty)
        let bought = await premium.purchase(.annual, entry: .settings)
        XCTAssertFalse(bought, "nothing to buy without real products")

        client.productFailure = nil
        await premium.loadProducts()
        XCTAssertEqual(premium.productsState, .loaded)
    }

    func testRestoreFindsAPurchaseOrSaysThereIsNone() async {
        let analytics = InMemoryAnalyticsTracker()
        let client = FakeStoreKitClient()
        let premium = PremiumTestKit.store(client, analytics: analytics)

        await premium.restore(entry: .settings)
        XCTAssertEqual(premium.restoreState, .nothingToRestore)
        XCTAssertFalse(premium.isPremium)
        XCTAssertEqual(client.syncCount, 1, "Restore calls AppStore.sync()")

        client.restorable = [client.activeTransaction(.annual)]
        await premium.restore(entry: .memoryBook)
        XCTAssertEqual(premium.restoreState, .restored)
        XCTAssertTrue(premium.isPremium)
        XCTAssertEqual(analytics.events.filter { $0.name == .premiumRestoreCompleted }.map { $0.properties["result"] }, ["nothing", "restored"])

        let offline = FakeStoreKitClient()
        offline.syncFailure = .network
        let offlineStore = PremiumTestKit.store(offline)
        await offlineStore.restore(entry: .settings)
        XCTAssertEqual(offlineStore.restoreState, .failed(StoreFailure.network.message), "never claims success")
    }

    func testTransactionUpdatesChangePremiumWhileRunning() async throws {
        let client = FakeStoreKitClient()
        let premium = PremiumTestKit.store(client)
        premium.start()
        try await PremiumTestKit.wait { premium.status != .unknown }
        XCTAssertFalse(premium.isPremium)

        // Approved Ask to Buy / a purchase on another device.
        client.deliverUpdate { $0.transactions = [client.activeTransaction(.monthly)] }
        try await PremiumTestKit.wait { premium.isPremium }

        // A refund.
        client.deliverUpdate { $0.transactions[0].revocationDate = Date() }
        try await PremiumTestKit.wait { !premium.isPremium }
        XCTAssertEqual(premium.status, .free(.revoked))
    }

    func testCachedPremiumIsForDisplayOnlyNeverForExports() async {
        let defaults = PremiumTestKit.defaults()
        defaults.set(true, forKey: PremiumStore.cachedPremiumKey)
        var used = FreeCreationAllowance()
        used.recordSuccessfulExport(of: .collageExport, decision: .allowedAsFreeCreation, at: Date())
        defaults.set(try? JSONEncoder().encode(used), forKey: PremiumStore.allowanceKey)

        // The App Store says: not subscribed (any more).
        let premium = PremiumTestKit.store(FakeStoreKitClient(), defaults: defaults)
        XCTAssertTrue(premium.showsPremium, "the last known answer avoids a flicker at launch")
        XCTAssertFalse(premium.isPremium)
        let decision = await premium.exportDecision(for: .collageExport)
        XCTAssertEqual(decision, .requiresPremium, "an export always waits for the verified answer")
        XCTAssertFalse(premium.showsPremium)
        XCTAssertFalse(defaults.bool(forKey: PremiumStore.cachedPremiumKey), "the cache follows StoreKit")
    }
}

@MainActor
final class FreeCreationAndGateTests: XCTestCase {
    private func image() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    func testFirstExportIsFreeThenThePaywallAppears() async {
        let analytics = InMemoryAnalyticsTracker()
        let defaults = PremiumTestKit.defaults()
        let premium = PremiumTestKit.store(defaults: defaults, analytics: analytics)
        let (store, _) = CollectionTestStore.make()
        let export = ExportController(saver: FakeCreationSaver(identifiers: ["saved-1", "saved-2"]))
        let gate = PremiumGate()
        XCTAssertTrue(premium.allowance.isAvailable)

        var performed = 0
        await gate.export(.collageExport, entry: .collageExport, premium: premium) { succeeded in
            performed += 1
            await export.save(store: store, analytics: analytics, properties: [:], onSaved: succeeded) { [self] in [image()] }
        }
        XCTAssertEqual(performed, 1)
        XCTAssertEqual(export.phase, .finished("Saved to Photos"))
        XCTAssertFalse(premium.allowance.isAvailable)
        XCTAssertEqual(premium.allowance.usedFor, .collageExport)
        XCTAssertNil(gate.request)
        XCTAssertEqual(analytics.events.filter { $0.name == .freeExportUsed }.count, 1)

        // The second export — of any kind covered by the free creation — asks for Premium.
        await gate.export(.storyExport, entry: .storyExport, premium: premium) { _ in performed += 1 }
        XCTAssertEqual(performed, 1, "nothing is exported behind the paywall")
        XCTAssertEqual(gate.request?.entry, .storyExport)
        XCTAssertTrue(analytics.events.contains { $0.name == .premiumFeatureTapped && $0.properties["entry"] == "story_export" })

        // Closing the paywall without subscribing does nothing.
        gate.request = nil
        gate.paywallDismissed(premium: premium)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(performed, 1)

        // Relaunch: still used.
        let relaunched = PremiumTestKit.store(defaults: defaults)
        XCTAssertFalse(relaunched.allowance.isAvailable)
        let decision = await relaunched.exportDecision(for: .collageExport)
        XCTAssertEqual(decision, .requiresPremium)
    }

    func testFailedExportAndPreviewDoNotUseTheFreeCreation() async {
        let premium = PremiumTestKit.store()
        let (store, _) = CollectionTestStore.make()
        let gate = PremiumGate()
        let failing = ExportController(saver: FailingSaver())
        await gate.export(.collageExport, entry: .collageExport, premium: premium) { succeeded in
            await failing.save(store: store, analytics: InMemoryAnalyticsTracker(), properties: [:], onSaved: succeeded) { [self] in [image()] }
        }
        guard case .failed = failing.phase else { return XCTFail("the save should have failed") }
        XCTAssertTrue(premium.allowance.isAvailable, "a failed export is not a free creation")

        let renderFailure = ExportController(saver: FakeCreationSaver(identifiers: ["x"]))
        await gate.export(.storyExport, entry: .storyExport, premium: premium) { succeeded in
            await renderFailure.save(store: store, analytics: InMemoryAnalyticsTracker(), properties: [:], onSaved: succeeded) { throw ExportFailure.failed }
        }
        XCTAssertTrue(premium.allowance.isAvailable)

        // Previews and editing never consult the gate; an editor can be built and changed freely.
        let trip = store.story.moments[0]
        let model = CollageEditorModel(source: .moment(trip.id), photos: Array(trip.assetIDs.prefix(4)), library: store.creationLibrary)
        model.movePhoto(model.photoIDs[0], toPositionOf: model.photoIDs[1])
        XCTAssertTrue(premium.allowance.isAvailable)
    }

    func testPremiumBypassesTheGateAndKeepsTheFreeCreation() async {
        let client = FakeStoreKitClient()
        client.snapshot.transactions = [client.activeTransaction(.annual)]
        let premium = PremiumTestKit.store(client)
        let gate = PremiumGate()
        var performed: [PremiumCapability] = []
        for capability in [PremiumCapability.collageExport, .storyExport, .trendExport, .memoryBookExport, .fullMonthlyRecap, .fullYearInReview] {
            await gate.export(capability, entry: .settings, premium: premium) { succeeded in
                performed.append(capability)
                succeeded()
            }
        }
        XCTAssertEqual(performed.count, 6)
        XCTAssertNil(gate.request)
        XCTAssertTrue(premium.allowance.isAvailable, "Premium exports never use the free creation")
        XCTAssertTrue(premium.hasAccess(to: .fullMonthlyRecap))
        XCTAssertTrue(premium.hasAccess(to: .fullYearInReview))
    }

    func testMemoryBookIsFreeToPreviewButSavingNeedsPremium() async throws {
        let premium = PremiumTestKit.store()
        let (store, _) = CollectionTestStore.make()
        // Making and laying out a book is free.
        let book = try MemoryBookBuilder(library: store.creationLibrary).makeBook(from: .moment(store.story.moments[0].id), now: Date()).get()
        store.saveBook(book)
        let layout = BookLayoutEngine(library: store.creationLibrary(for: book)).layout(book)
        XCTAssertFalse(layout.pages.isEmpty)

        let gate = PremiumGate()
        var saved = false
        await gate.export(.memoryBookExport, entry: .memoryBook, premium: premium, heroAssetID: layout.photoIDs.first) { _ in saved = true }
        XCTAssertFalse(saved)
        XCTAssertEqual(gate.request?.entry, .memoryBook)
        XCTAssertEqual(gate.request?.heroAssetID, layout.photoIDs.first)
        XCTAssertTrue(premium.allowance.isAvailable, "the free creation isn't spent on a book")
    }

    func testSubscribingFromThePaywallFinishesTheExport() async throws {
        let client = FakeStoreKitClient()
        let premium = PremiumTestKit.store(client)
        await premium.loadProducts()
        let gate = PremiumGate()
        var saved = false
        await gate.export(.memoryBookExport, entry: .memoryBook, premium: premium) { succeeded in
            saved = true
            succeeded()
        }
        XCTAssertNotNil(gate.request)
        let bought = await premium.purchase(.annual, entry: .memoryBook)
        XCTAssertTrue(bought)
        gate.request = nil
        gate.paywallDismissed(premium: premium)
        try await PremiumTestKit.wait { saved }
    }

    func testRecapPreviewsStayFreeAndTheArchiveIsUntouched() async {
        let premium = PremiumTestKit.store()
        await premium.refreshEntitlements()
        let (store, _) = CollectionTestStore.make()
        XCTAssertFalse(premium.hasAccess(to: .fullMonthlyRecap))
        XCTAssertFalse(premium.hasAccess(to: .fullYearInReview))

        // The preview's data is all there for a free user: months, counts, highlights, moments.
        let library = store.creationLibrary
        let index = TemporalIndex(library: library)
        let month = try? XCTUnwrap(index.months.first)
        if let month {
            let recap = MonthlyRecapBuilder(library: library).recap(for: month, index: index)
            XCTAssertGreaterThan(recap.statistics.memoryCount, 0)
            XCTAssertFalse(recap.moments.isEmpty)
        }
        let year = index.years.first.map { YearInReviewBuilder(library: library).review(for: $0, index: index) }
        XCTAssertNotNil(year)

        // The archive never asks: story, statistics, favorites and notes work as before.
        XCTAssertFalse(store.story.moments.isEmpty)
        let moment = store.story.moments[0]
        store.setFavorite(.moment, moment.id.uuidString, isFavorite: true)
        XCTAssertTrue(store.isFavorite(.moment, moment.id.uuidString))
        XCTAssertGreaterThan(store.statistics.memoryCount, 0)
    }
}
