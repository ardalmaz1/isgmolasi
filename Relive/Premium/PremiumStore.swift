import Foundation
import Observation
import ReliveCore

/// The one source of truth for Premium: verified entitlements, products, purchase and restore,
/// and the one free creation. Screens read it; none of them talks to StoreKit.
///
/// Premium is always derived from StoreKit's verified data (`EntitlementResolver`). The last
/// known answer is cached only so the UI doesn't flicker at launch; it never unlocks an export,
/// which always waits for a fresh check.
@Observable
@MainActor
final class PremiumStore {
    enum ProductsState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum PurchaseState: Equatable {
        case idle
        case purchasing(PremiumProductRole)
        /// Waiting for approval; Premium arrives through a transaction update if approved.
        case pending
        case failed(String)
    }

    enum RestoreState: Equatable {
        case idle
        case restoring
        case restored
        case nothingToRestore
        case failed(String)
    }

    private(set) var status: EntitlementStatus = .unknown
    /// Annual first.
    private(set) var products: [PremiumProduct] = []
    private(set) var productsState: ProductsState = .idle
    private(set) var purchaseState: PurchaseState = .idle
    private(set) var restoreState: RestoreState = .idle
    private(set) var allowance: FreeCreationAllowance

    @ObservationIgnored private let client: any StoreKitClient
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let analytics: any AnalyticsTracking
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var cachedPremium: Bool
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    static let allowanceKey = "relive.commercial.freeCreation"
    static let cachedPremiumKey = "relive.commercial.lastKnownPremium"

    init(client: any StoreKitClient, defaults: UserDefaults = .standard, analytics: any AnalyticsTracking, now: @escaping () -> Date = Date.init) {
        self.client = client
        self.defaults = defaults
        self.analytics = analytics
        self.now = now
        allowance = defaults.data(forKey: Self.allowanceKey).flatMap { try? JSONDecoder().decode(FreeCreationAllowance.self, from: $0) } ?? FreeCreationAllowance()
        cachedPremium = defaults.bool(forKey: Self.cachedPremiumKey)
    }

    // MARK: - Reading

    /// Verified Premium, checked this launch.
    var isPremium: Bool { status.isPremium }

    /// For showing things (badges, the full recap): the verified answer, or until the first
    /// check finishes, the last known one. Never used to allow an export.
    var showsPremium: Bool {
        status == .unknown ? cachedPremium : status.isPremium
    }

    /// May the user see this in full?
    func hasAccess(to capability: PremiumCapability) -> Bool {
        PremiumPolicy.hasAccess(to: capability, isPremium: showsPremium)
    }

    var annual: PremiumProduct? { products.first { $0.role == .annual } }
    var monthly: PremiumProduct? { products.first { $0.role == .monthly } }

    // MARK: - Lifecycle

    /// Starts listening for transaction updates, checks entitlements and loads products. Safe to
    /// call more than once.
    func start() {
        if updatesTask == nil {
            let updates = client.transactionUpdates()
            updatesTask = Task { [weak self] in
                for await _ in updates {
                    await self?.refreshEntitlements()
                }
            }
        }
        Task { await refreshEntitlements() }
        if productsState != .loaded {
            Task { await loadProducts() }
        }
    }

    /// Re-derives Premium from StoreKit's current entitlements.
    func refreshEntitlements() async {
        let snapshot = await client.entitlements()
        let resolved = EntitlementResolver.resolve(transactions: snapshot.transactions, statuses: snapshot.statuses, now: now())
        apply(resolved)
    }

    private func apply(_ resolved: EntitlementStatus) {
        status = resolved
        cachedPremium = resolved.isPremium
        defaults.set(resolved.isPremium, forKey: Self.cachedPremiumKey)
        if resolved.isPremium, case .pending = purchaseState { purchaseState = .idle }
    }

    /// Waits for a fresh entitlement check if none has happened this launch.
    private func ensureResolved() async {
        if status == .unknown { await refreshEntitlements() }
    }

    func loadProducts() async {
        guard productsState != .loading else { return }
        productsState = .loading
        do {
            let loaded = try await client.loadProducts(ids: PremiumProductRole.productIDs)
            products = loaded.sorted { $0.role == .annual && $1.role != .annual }
            productsState = loaded.isEmpty ? .failed("Premium isn’t available right now. Please try again later.") : .loaded
        } catch {
            productsState = .failed(Self.failure(error).message)
        }
    }

    // MARK: - Purchasing

    /// Buys `role`. Returns true once Premium is verified.
    @discardableResult
    func purchase(_ role: PremiumProductRole, entry: PaywallEntryPoint) async -> Bool {
        if case .purchasing = purchaseState { return false }
        guard let product = products.first(where: { $0.role == role }) else {
            purchaseState = .failed("Prices haven’t loaded yet. Please try again.")
            return false
        }
        let properties = ["entry": entry.rawValue, "product": role.rawValue]
        analytics.track(.premiumPurchaseStarted, properties)
        purchaseState = .purchasing(role)
        do {
            switch try await client.purchase(productID: product.id) {
            case .purchased:
                await refreshEntitlements()
                if isPremium {
                    purchaseState = .idle
                    analytics.track(.premiumPurchaseCompleted, properties)
                    return true
                }
                purchaseState = .failed("The purchase couldn’t be confirmed. If you were charged, use Restore Purchases.")
                analytics.track(.premiumPurchaseFailed, properties.merging(["reason": "not_entitled"]) { $1 })
            case .cancelled:
                purchaseState = .idle
                analytics.track(.premiumPurchaseCancelled, properties)
            case .pending:
                purchaseState = .pending
                analytics.track(.premiumPurchasePending, properties)
            case .unverified:
                purchaseState = .failed("The App Store couldn’t verify this purchase, so Premium wasn’t turned on. Please try Restore Purchases.")
                analytics.track(.premiumPurchaseFailed, properties.merging(["reason": "unverified"]) { $1 })
            }
        } catch {
            let failure = Self.failure(error)
            purchaseState = .failed(failure.message)
            analytics.track(.premiumPurchaseFailed, properties.merging(["reason": "\(failure)"]) { $1 })
        }
        return false
    }

    func clearPurchaseMessage() {
        if case .purchasing = purchaseState { return }
        purchaseState = .idle
    }

    /// Restore Purchases: syncs with the App Store, then re-checks verified entitlements.
    func restore(entry: PaywallEntryPoint) async {
        guard restoreState != .restoring else { return }
        restoreState = .restoring
        analytics.track(.premiumRestoreStarted, ["entry": entry.rawValue])
        do {
            try await client.sync()
        } catch {
            // Even if sync fails, what's already on this device still counts.
            await refreshEntitlements()
            restoreState = isPremium ? .restored : .failed(Self.failure(error).message)
            analytics.track(.premiumRestoreCompleted, ["entry": entry.rawValue, "result": isPremium ? "restored" : "failed"])
            return
        }
        await refreshEntitlements()
        restoreState = isPremium ? .restored : .nothingToRestore
        analytics.track(.premiumRestoreCompleted, ["entry": entry.rawValue, "result": isPremium ? "restored" : "nothing"])
    }

    func clearRestoreMessage() {
        if restoreState != .restoring { restoreState = .idle }
    }

    // MARK: - Exports

    /// May the user keep this creation now? Always checks entitlements first.
    func exportDecision(for capability: PremiumCapability) async -> ExportDecision {
        await ensureResolved()
        return PremiumPolicy.exportDecision(for: capability, isPremium: isPremium, allowance: allowance)
    }

    /// Call when a save or share actually succeeded. Uses the free creation only if that's what
    /// allowed the export.
    func recordSuccessfulExport(of capability: PremiumCapability, decision: ExportDecision) {
        guard allowance.recordSuccessfulExport(of: capability, decision: decision, at: now()) else { return }
        if let data = try? JSONEncoder().encode(allowance) {
            defaults.set(data, forKey: Self.allowanceKey)
        }
        analytics.track(.freeExportUsed, ["feature": capability.rawValue])
    }

    func trackPremiumFeatureTapped(_ entry: PaywallEntryPoint) {
        analytics.track(.premiumFeatureTapped, ["entry": entry.rawValue, "feature": entry.capability?.rawValue ?? "none"])
    }

    func trackPaywall(viewed entry: PaywallEntryPoint) {
        analytics.track(.paywallViewed, ["entry": entry.rawValue])
    }

    func trackPaywall(closed entry: PaywallEntryPoint) {
        analytics.track(.paywallClosed, ["entry": entry.rawValue, "premium": isPremium ? "true" : "false"])
    }

    private static func failure(_ error: any Error) -> StoreFailure {
        error as? StoreFailure ?? .unknown
    }

    #if DEBUG
    /// UI tests only (`-ReliveUITestStartFresh`): forget the free creation and the cache.
    static func eraseLocalState(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: allowanceKey)
        defaults.removeObject(forKey: cachedPremiumKey)
    }
    #endif
}
