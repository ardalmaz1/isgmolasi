import Foundation

/// The subscription products, by role. Prices, names and trials come from the App Store.
public enum PremiumProductRole: String, CaseIterable, Codable, Sendable {
    case annual
    case monthly

    public var productID: String {
        switch self {
        case .annual: "relive.premium.annual"
        case .monthly: "relive.premium.monthly"
        }
    }

    public init?(productID: String) {
        guard let role = Self.allCases.first(where: { $0.productID == productID }) else { return nil }
        self = role
    }

    public static var productIDs: [String] { allCases.map(\.productID) }
}

/// A transaction as the entitlement rules need it — StoreKit-free, so the rules run (and are
/// tested) anywhere. `isVerified` is StoreKit's own JWS verification result.
public struct EntitlementTransaction: Equatable, Sendable {
    public var productID: String
    public var isVerified: Bool
    public var purchaseDate: Date
    public var expirationDate: Date?
    public var revocationDate: Date?
    public var isUpgraded: Bool

    public init(productID: String, isVerified: Bool, purchaseDate: Date, expirationDate: Date?, revocationDate: Date? = nil, isUpgraded: Bool = false) {
        self.productID = productID
        self.isVerified = isVerified
        self.purchaseDate = purchaseDate
        self.expirationDate = expirationDate
        self.revocationDate = revocationDate
        self.isUpgraded = isUpgraded
    }
}

/// A subscription's renewal state (StoreKit's `Product.SubscriptionInfo.RenewalState`).
public enum SubscriptionRenewalState: String, Equatable, Sendable {
    case subscribed
    case expired
    case inBillingRetryPeriod
    case inGracePeriod
    case revoked
}

/// One subscription status from the App Store.
public struct SubscriptionStatusSnapshot: Equatable, Sendable {
    public var productID: String
    public var state: SubscriptionRenewalState
    /// The status's own transaction and renewal info both verified.
    public var isVerified: Bool
    public var expirationDate: Date?
    public var willAutoRenew: Bool

    public init(productID: String, state: SubscriptionRenewalState, isVerified: Bool, expirationDate: Date? = nil, willAutoRenew: Bool = true) {
        self.productID = productID
        self.state = state
        self.isVerified = isVerified
        self.expirationDate = expirationDate
        self.willAutoRenew = willAutoRenew
    }
}

/// An active Premium entitlement.
public struct PremiumGrant: Equatable, Sendable {
    public var role: PremiumProductRole
    public var expirationDate: Date?
    public var willAutoRenew: Bool
    /// Billing failed but Apple keeps access during the grace period.
    public var isInGracePeriod: Bool

    public init(role: PremiumProductRole, expirationDate: Date?, willAutoRenew: Bool = true, isInGracePeriod: Bool = false) {
        self.role = role
        self.expirationDate = expirationDate
        self.willAutoRenew = willAutoRenew
        self.isInGracePeriod = isInGracePeriod
    }
}

/// Why someone who once subscribed isn't Premium now — said calmly, never used to nag.
public enum EntitlementNotice: String, Equatable, Sendable {
    case expired
    case revoked
    /// Apple is retrying a failed payment (no grace period): access pauses until it succeeds.
    case billingRetry
    /// Something claimed a purchase but didn't verify: ignored.
    case verificationFailed
}

public enum EntitlementStatus: Equatable, Sendable {
    /// Not checked yet this launch.
    case unknown
    case free(EntitlementNotice?)
    case premium(PremiumGrant)

    public var isPremium: Bool {
        if case .premium = self { return true }
        return false
    }

    public var grant: PremiumGrant? {
        if case .premium(let grant) = self { return grant }
        return nil
    }
}

/// Derives Premium from StoreKit's verified data only. An unverified transaction or status never
/// grants Premium, whatever it says.
public enum EntitlementResolver {
    public static func resolve(
        transactions: [EntitlementTransaction],
        statuses: [SubscriptionStatusSnapshot] = [],
        now: Date
    ) -> EntitlementStatus {
        let known = transactions.filter { PremiumProductRole(productID: $0.productID) != nil }
        let knownStatuses = statuses.filter { PremiumProductRole(productID: $0.productID) != nil }

        // 1. A verified, unrevoked, current transaction.
        let active = known.filter { transaction in
            transaction.isVerified
                && transaction.revocationDate == nil
                && !transaction.isUpgraded
                && (transaction.expirationDate.map { $0 > now } ?? true)
        }
        // The annual plan wins if both are somehow active, then the latest expiry.
        if let best = active.max(by: { rank($0) < rank($1) }), let role = PremiumProductRole(productID: best.productID) {
            let status = knownStatuses.first { $0.productID == best.productID && $0.isVerified }
            return .premium(PremiumGrant(
                role: role,
                expirationDate: best.expirationDate,
                willAutoRenew: status?.willAutoRenew ?? true,
                isInGracePeriod: status?.state == .inGracePeriod
            ))
        }

        // 2. Apple's grace period: billing failed but access continues.
        if let grace = knownStatuses.first(where: { $0.isVerified && $0.state == .inGracePeriod }),
           let role = PremiumProductRole(productID: grace.productID) {
            return .premium(PremiumGrant(role: role, expirationDate: grace.expirationDate, willAutoRenew: grace.willAutoRenew, isInGracePeriod: true))
        }

        // 3. Not Premium — and, if there's a reason worth knowing, why.
        let verifiedStatuses = knownStatuses.filter(\.isVerified)
        if verifiedStatuses.contains(where: { $0.state == .inBillingRetryPeriod }) { return .free(.billingRetry) }
        if known.contains(where: { $0.isVerified && $0.revocationDate != nil }) || verifiedStatuses.contains(where: { $0.state == .revoked }) {
            return .free(.revoked)
        }
        if known.contains(where: { $0.isVerified }) || verifiedStatuses.contains(where: { $0.state == .expired }) {
            return .free(.expired)
        }
        if known.contains(where: { !$0.isVerified }) || knownStatuses.contains(where: { !$0.isVerified }) {
            return .free(.verificationFailed)
        }
        return .free(nil)
    }

    private static func rank(_ transaction: EntitlementTransaction) -> (Int, Date) {
        let annual = transaction.productID == PremiumProductRole.annual.productID ? 1 : 0
        return (annual, transaction.expirationDate ?? .distantFuture)
    }
}
