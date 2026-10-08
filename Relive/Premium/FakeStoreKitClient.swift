import Foundation
import ReliveCore

/// A StoreKit stand-in for tests and UI tests: no App Store, no network, no real money.
/// Everything it reports goes through the same entitlement rules as the real App Store data.
final class FakeStoreKitClient: StoreKitClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _products: [PremiumProduct]
    private var _productFailure: StoreFailure?
    private var _purchaseOutcome: PurchaseOutcome = .purchased
    private var _purchaseFailure: StoreFailure?
    private var _snapshot = EntitlementSnapshot()
    private var _syncFailure: StoreFailure?
    /// What a restore finds in the App Store (added on `sync()`).
    private var _restorable: [EntitlementTransaction] = []
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]
    private(set) var purchaseCount = 0
    private(set) var syncCount = 0
    var now: () -> Date = Date.init

    init(products: [PremiumProduct] = FakeStoreKitClient.sampleProducts(withTrial: false)) {
        _products = products
    }

    // MARK: Configuration

    var products: [PremiumProduct] {
        get { lock.withLock { _products } }
        set { lock.withLock { _products = newValue } }
    }
    var productFailure: StoreFailure? {
        get { lock.withLock { _productFailure } }
        set { lock.withLock { _productFailure = newValue } }
    }
    var purchaseOutcome: PurchaseOutcome {
        get { lock.withLock { _purchaseOutcome } }
        set { lock.withLock { _purchaseOutcome = newValue } }
    }
    var purchaseFailure: StoreFailure? {
        get { lock.withLock { _purchaseFailure } }
        set { lock.withLock { _purchaseFailure = newValue } }
    }
    var snapshot: EntitlementSnapshot {
        get { lock.withLock { _snapshot } }
        set { lock.withLock { _snapshot = newValue } }
    }
    var syncFailure: StoreFailure? {
        get { lock.withLock { _syncFailure } }
        set { lock.withLock { _syncFailure = newValue } }
    }
    var restorable: [EntitlementTransaction] {
        get { lock.withLock { _restorable } }
        set { lock.withLock { _restorable = newValue } }
    }

    /// Simulates a transaction arriving from outside (renewal, refund, Ask to Buy approval).
    func deliverUpdate(_ change: (inout EntitlementSnapshot) -> Void) {
        let continuations = lock.withLock {
            change(&_snapshot)
            return Array(self.continuations.values)
        }
        for continuation in continuations { continuation.yield() }
    }

    /// A verified transaction for `role`, valid for its period from now.
    func activeTransaction(_ role: PremiumProductRole, verified: Bool = true) -> EntitlementTransaction {
        let start = now()
        let length: TimeInterval = role == .annual ? 365 * 86_400 : 30 * 86_400
        return EntitlementTransaction(productID: role.productID, isVerified: verified, purchaseDate: start, expirationDate: start.addingTimeInterval(length))
    }

    // MARK: StoreKitClient

    func loadProducts(ids: [String]) async throws -> [PremiumProduct] {
        let (products, failure) = lock.withLock { (_products, _productFailure) }
        if let failure { throw failure }
        return products.filter { ids.contains($0.id) }
    }

    func purchase(productID: String) async throws -> PurchaseOutcome {
        let (failure, outcome, known) = lock.withLock { (_purchaseFailure, _purchaseOutcome, _products.contains { $0.id == productID }) }
        if let failure { throw failure }
        guard known, let role = PremiumProductRole(productID: productID) else { throw StoreFailure.productUnavailable }
        lock.withLock { purchaseCount += 1 }
        if outcome == .purchased {
            let transaction = activeTransaction(role)
            lock.withLock { _snapshot.transactions.append(transaction) }
        }
        return outcome
    }

    func entitlements() async -> EntitlementSnapshot {
        snapshot
    }

    func sync() async throws {
        let failure = lock.withLock {
            syncCount += 1
            return _syncFailure
        }
        if let failure { throw failure }
        lock.withLock {
            for transaction in _restorable where !_snapshot.transactions.contains(transaction) {
                _snapshot.transactions.append(transaction)
            }
        }
    }

    func transactionUpdates() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let id = UUID()
            lock.withLock { continuations[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.withLock { _ = self.continuations.removeValue(forKey: id) }
            }
        }
    }

    // MARK: Samples

    /// Placeholder products for tests only. Real names, prices and trials come from App Store
    /// Connect (or `StoreKit/Relive.storekit` when running from Xcode).
    static func sampleProducts(withTrial: Bool) -> [PremiumProduct] {
        [
            PremiumProduct(
                id: PremiumProductRole.annual.productID,
                role: .annual,
                displayName: "Relive Premium Annual",
                displayPrice: "$39.99",
                period: SubscriptionPeriod(value: 1, unit: .year),
                introductoryOffer: withTrial ? IntroductoryOffer(paymentMode: .freeTrial, period: SubscriptionPeriod(value: 1, unit: .week), displayPrice: "$0.00") : nil,
                isEligibleForIntroOffer: withTrial
            ),
            PremiumProduct(
                id: PremiumProductRole.monthly.productID,
                role: .monthly,
                displayName: "Relive Premium Monthly",
                displayPrice: "$4.99",
                period: SubscriptionPeriod(value: 1, unit: .month)
            ),
        ]
    }
}
