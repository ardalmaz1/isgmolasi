import Foundation
import ReliveCore
import StoreKit

/// What the App Store said about a purchase.
enum PurchaseOutcome: Equatable, Sendable {
    /// Verified and finished.
    case purchased
    case cancelled
    /// Waiting for approval (Ask to Buy, Strong Customer Authentication).
    case pending
    /// The App Store returned a transaction that didn't verify: never treated as a purchase.
    case unverified
}

/// Why talking to the App Store failed, in words for the user.
enum StoreFailure: Error, Equatable, Sendable {
    case network
    /// StoreKit isn't available here (no App Store account, restricted, unsupported storefront).
    case unavailable
    /// The device or account isn't allowed to make purchases.
    case purchaseNotAllowed
    case productUnavailable
    case unknown

    var message: String {
        switch self {
        case .network: "You seem to be offline. Check your connection and try again."
        case .unavailable: "The App Store isn’t available right now. Please try again later."
        case .purchaseNotAllowed: "Purchases aren’t allowed on this iPhone or App Store account."
        case .productUnavailable: "Premium isn’t available in your region right now."
        case .unknown: "Something went wrong with the App Store. Please try again."
        }
    }
}

/// The App Store's view of this user's entitlements.
struct EntitlementSnapshot: Equatable, Sendable {
    var transactions: [EntitlementTransaction] = []
    var statuses: [SubscriptionStatusSnapshot] = []
}

/// Everything Relive asks of StoreKit. The app uses `LiveStoreKitClient`; tests and UI tests use
/// `FakeStoreKitClient`, so CI never depends on a live App Store.
/// Methods throw `StoreFailure`.
protocol StoreKitClient: Sendable {
    func loadProducts(ids: [String]) async throws -> [PremiumProduct]
    func purchase(productID: String) async throws -> PurchaseOutcome
    /// Current entitlements (verified and not) and subscription statuses.
    func entitlements() async -> EntitlementSnapshot
    /// Restore Purchases: `AppStore.sync()`.
    func sync() async throws
    /// Yields whenever a transaction arrives from outside a purchase call (renewal, refund,
    /// Ask to Buy approval, a purchase on another device).
    func transactionUpdates() -> AsyncStream<Void>
}

// MARK: - StoreKit 2

/// StoreKit 2. Products are kept after loading so a purchase uses the same `Product`.
struct LiveStoreKitClient: StoreKitClient {
    private let cache = ProductCache()

    func loadProducts(ids: [String]) async throws -> [PremiumProduct] {
        let products: [Product]
        do {
            products = try await Product.products(for: ids)
        } catch {
            throw Self.failure(error)
        }
        await cache.store(products)
        var result: [PremiumProduct] = []
        for product in products {
            guard let role = PremiumProductRole(productID: product.id), let subscription = product.subscription else { continue }
            let eligible = await subscription.isEligibleForIntroOffer
            result.append(PremiumProduct(
                id: product.id,
                role: role,
                displayName: product.displayName,
                displayPrice: product.displayPrice,
                period: Self.period(subscription.subscriptionPeriod),
                introductoryOffer: subscription.introductoryOffer.map(Self.offer),
                isEligibleForIntroOffer: eligible
            ))
        }
        return result
    }

    func purchase(productID: String) async throws -> PurchaseOutcome {
        var product = await cache.product(productID)
        if product == nil {
            product = try? await Product.products(for: [productID]).first
        }
        guard let product else { throw StoreFailure.productUnavailable }
        let result: Product.PurchaseResult
        do {
            result = try await product.purchase()
        } catch {
            throw Self.failure(error)
        }
        switch result {
        case .success(.verified(let transaction)):
            await transaction.finish()
            return .purchased
        case .success(.unverified):
            // Never granted, never finished as if it were good.
            return .unverified
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            return .cancelled
        }
    }

    func entitlements() async -> EntitlementSnapshot {
        var snapshot = EntitlementSnapshot()
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                snapshot.transactions.append(Self.entitlement(transaction, verified: true))
            case .unverified(let transaction, _):
                snapshot.transactions.append(Self.entitlement(transaction, verified: false))
            }
        }
        // One subscription group: any of its products reports the group's statuses.
        if let product = await cache.anyProduct(), let statuses = try? await product.subscription?.status {
            for status in statuses {
                guard let mapped = Self.status(status) else { continue }
                snapshot.statuses.append(mapped)
            }
        }
        return snapshot
    }

    func sync() async throws {
        do {
            try await AppStore.sync()
        } catch {
            throw Self.failure(error)
        }
    }

    func transactionUpdates() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .utility) {
                for await result in Transaction.updates {
                    if case .verified(let transaction) = result {
                        await transaction.finish()
                    }
                    continuation.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Mapping

    private static func entitlement(_ transaction: Transaction, verified: Bool) -> EntitlementTransaction {
        EntitlementTransaction(
            productID: transaction.productID,
            isVerified: verified,
            purchaseDate: transaction.purchaseDate,
            expirationDate: transaction.expirationDate,
            revocationDate: transaction.revocationDate,
            isUpgraded: transaction.isUpgraded
        )
    }

    private static func status(_ status: Product.SubscriptionInfo.Status) -> SubscriptionStatusSnapshot? {
        let transaction: Transaction
        var verified = true
        switch status.transaction {
        case .verified(let value): transaction = value
        case .unverified(let value, _): transaction = value; verified = false
        }
        var willAutoRenew = false
        switch status.renewalInfo {
        case .verified(let info): willAutoRenew = info.willAutoRenew
        case .unverified(let info, _): willAutoRenew = info.willAutoRenew; verified = false
        }
        let state: SubscriptionRenewalState
        switch status.state {
        case .subscribed: state = .subscribed
        case .expired: state = .expired
        case .inBillingRetryPeriod: state = .inBillingRetryPeriod
        case .inGracePeriod: state = .inGracePeriod
        case .revoked: state = .revoked
        default: return nil
        }
        return SubscriptionStatusSnapshot(
            productID: transaction.productID,
            state: state,
            isVerified: verified,
            expirationDate: transaction.expirationDate,
            willAutoRenew: willAutoRenew
        )
    }

    private static func period(_ period: Product.SubscriptionPeriod) -> ReliveCore.SubscriptionPeriod {
        let unit: ReliveCore.SubscriptionPeriod.Unit = switch period.unit {
        case .day: .day
        case .week: .week
        case .month: .month
        case .year: .year
        @unknown default: .month
        }
        return ReliveCore.SubscriptionPeriod(value: period.value, unit: unit)
    }

    private static func offer(_ offer: Product.SubscriptionOffer) -> ReliveCore.IntroductoryOffer {
        let mode: ReliveCore.IntroductoryOffer.PaymentMode = switch offer.paymentMode {
        case .freeTrial: .freeTrial
        case .payUpFront: .payUpFront
        default: .payAsYouGo
        }
        return ReliveCore.IntroductoryOffer(paymentMode: mode, period: period(offer.period), periodCount: offer.periodCount, displayPrice: offer.displayPrice)
    }

    private static func failure(_ error: any Error) -> StoreFailure {
        if let error = error as? StoreKitError {
            switch error {
            case .networkError: return .network
            case .notAvailableInStorefront: return .productUnavailable
            case .notEntitled: return .purchaseNotAllowed
            case .userCancelled: return .unknown
            default: return .unavailable
            }
        }
        if let error = error as? Product.PurchaseError {
            switch error {
            case .purchaseNotAllowed: return .purchaseNotAllowed
            case .productUnavailable: return .productUnavailable
            default: return .unknown
            }
        }
        if (error as NSError).domain == NSURLErrorDomain { return .network }
        return .unknown
    }
}

/// Products loaded this launch.
private actor ProductCache {
    private var products: [String: Product] = [:]

    func store(_ loaded: [Product]) {
        for product in loaded { products[product.id] = product }
    }

    func product(_ id: String) -> Product? { products[id] }

    func anyProduct() -> Product? {
        for id in PremiumProductRole.productIDs {
            if let product = products[id] { return product }
        }
        return nil
    }
}
