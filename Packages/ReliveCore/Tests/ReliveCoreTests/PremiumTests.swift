import Foundation
import Testing
@testable import ReliveCore

private let now = Date(timeIntervalSince1970: 1_790_000_000)
private let annualID = PremiumProductRole.annual.productID
private let monthlyID = PremiumProductRole.monthly.productID

private func transaction(_ id: String = annualID, verified: Bool = true, expires: TimeInterval? = 86_400, revoked: Bool = false, upgraded: Bool = false) -> EntitlementTransaction {
    EntitlementTransaction(
        productID: id,
        isVerified: verified,
        purchaseDate: now.addingTimeInterval(-86_400),
        expirationDate: expires.map { now.addingTimeInterval($0) },
        revocationDate: revoked ? now.addingTimeInterval(-60) : nil,
        isUpgraded: upgraded
    )
}

@Suite("Premium: free creation and gating")
struct PremiumGatingTests {
    @Test func theFreeCreationIsAvailableAtFirst() {
        let allowance = FreeCreationAllowance()
        #expect(allowance.isAvailable)
        #expect(PremiumPolicy.exportDecision(for: .collageExport, isPremium: false, allowance: allowance) == .allowedAsFreeCreation)
        #expect(PremiumPolicy.exportDecision(for: .storyExport, isPremium: false, allowance: allowance) == .allowedAsFreeCreation)
    }

    @Test func previewsAndFailedExportsDoNotUseIt() {
        var allowance = FreeCreationAllowance()
        // A preview never asks for a decision; a failed export never reports success.
        // Reporting a Premium export, or one that wasn't the free creation, changes nothing.
        let r1 = allowance.recordSuccessfulExport(of: .collageExport, decision: .allowed, at: now)
        #expect(!r1)
        let r2 = allowance.recordSuccessfulExport(of: .collageExport, decision: .requiresPremium, at: now)
        #expect(!r2)
        #expect(allowance.isAvailable)
    }

    @Test func aSuccessfulFreeExportUsesIt() {
        var allowance = FreeCreationAllowance()
        let r3 = allowance.recordSuccessfulExport(of: .storyExport, decision: .allowedAsFreeCreation, at: now)
        #expect(r3)
        #expect(!allowance.isAvailable)
        #expect(allowance.usedFor == .storyExport)
        #expect(allowance.usedAt == now)
        // Only once.
        let r4 = allowance.recordSuccessfulExport(of: .collageExport, decision: .allowedAsFreeCreation, at: now.addingTimeInterval(5))
        #expect(!r4)
        #expect(allowance.usedAt == now)
        #expect(PremiumPolicy.exportDecision(for: .collageExport, isPremium: false, allowance: allowance) == .requiresPremium)
        #expect(PremiumPolicy.exportDecision(for: .storyExport, isPremium: false, allowance: allowance) == .requiresPremium)
    }

    @Test func theAllowancePersists() throws {
        var allowance = FreeCreationAllowance()
        allowance.recordSuccessfulExport(of: .collageExport, decision: .allowedAsFreeCreation, at: now)
        let data = try JSONEncoder().encode(allowance)
        let decoded = try JSONDecoder().decode(FreeCreationAllowance.self, from: data)
        #expect(decoded == allowance)
        #expect(!decoded.isAvailable)
    }

    @Test func premiumBypassesEveryGate() {
        var used = FreeCreationAllowance()
        used.recordSuccessfulExport(of: .collageExport, decision: .allowedAsFreeCreation, at: now)
        for capability in PremiumCapability.allCases {
            #expect(PremiumPolicy.exportDecision(for: capability, isPremium: true, allowance: used) == .allowed)
            #expect(PremiumPolicy.hasAccess(to: capability, isPremium: true))
        }
    }

    @Test func memoryBookExportNeedsPremiumEvenWithTheFreeCreation() {
        let fresh = FreeCreationAllowance()
        #expect(PremiumPolicy.exportDecision(for: .memoryBookExport, isPremium: false, allowance: fresh) == .requiresPremium)
        #expect(!PremiumPolicy.hasAccess(to: .memoryBookExport, isPremium: false))
    }

    @Test func recapsInFullArePremiumButNeverTheArchive() {
        #expect(!PremiumPolicy.hasAccess(to: .fullMonthlyRecap, isPremium: false))
        #expect(!PremiumPolicy.hasAccess(to: .fullYearInReview, isPremium: false))
        // Nothing about memories, moments, places, notes, favorites or hidden memories is a
        // capability at all: the archive can't be gated by construction.
        let names = PremiumCapability.allCases.map(\.rawValue).joined(separator: " ")
        for archive in ["moment", "place", "note", "favorite", "hidden", "timeline", "story_view"] {
            #expect(!names.contains(archive))
        }
        #expect(PremiumCapability.allCases.filter(\.isCoveredByFreeCreation) == [.collageExport, .storyExport, .trendExport])
    }
}

@Suite("Premium: entitlement from StoreKit data")
struct EntitlementResolverTests {
    @Test func aVerifiedActiveSubscriptionIsPremium() {
        let status = EntitlementResolver.resolve(transactions: [transaction()], now: now)
        #expect(status.isPremium)
        #expect(status.grant?.role == .annual)
    }

    @Test func anUnverifiedTransactionIsIgnored() {
        let status = EntitlementResolver.resolve(transactions: [transaction(verified: false)], now: now)
        #expect(status == .free(.verificationFailed))
        // Even with an unverified "subscribed" status alongside it.
        let withStatus = EntitlementResolver.resolve(
            transactions: [transaction(verified: false)],
            statuses: [SubscriptionStatusSnapshot(productID: annualID, state: .inGracePeriod, isVerified: false)],
            now: now
        )
        #expect(!withStatus.isPremium)
    }

    @Test func anExpiredSubscriptionIsNotPremium() {
        let status = EntitlementResolver.resolve(transactions: [transaction(expires: -60)], now: now)
        #expect(status == .free(.expired))
        let byStatus = EntitlementResolver.resolve(
            transactions: [],
            statuses: [SubscriptionStatusSnapshot(productID: monthlyID, state: .expired, isVerified: true)],
            now: now
        )
        #expect(byStatus == .free(.expired))
    }

    @Test func aRevokedSubscriptionIsNotPremium() {
        let status = EntitlementResolver.resolve(transactions: [transaction(revoked: true)], now: now)
        #expect(status == .free(.revoked))
    }

    @Test func billingRetryPausesButGracePeriodKeepsAccess() {
        let retry = EntitlementResolver.resolve(
            transactions: [transaction(expires: -60)],
            statuses: [SubscriptionStatusSnapshot(productID: annualID, state: .inBillingRetryPeriod, isVerified: true)],
            now: now
        )
        #expect(retry == .free(.billingRetry))
        let grace = EntitlementResolver.resolve(
            transactions: [transaction(expires: -60)],
            statuses: [SubscriptionStatusSnapshot(productID: annualID, state: .inGracePeriod, isVerified: true)],
            now: now
        )
        #expect(grace.isPremium)
        #expect(grace.grant?.isInGracePeriod == true)
    }

    @Test func upgradedAndUnknownProductsDontCount() {
        #expect(!EntitlementResolver.resolve(transactions: [transaction(upgraded: true)], now: now).isPremium)
        #expect(EntitlementResolver.resolve(transactions: [transaction("someone.else.product")], now: now) == .free(nil))
        #expect(EntitlementResolver.resolve(transactions: [], now: now) == .free(nil))
    }

    @Test func annualWinsWhenBothAreActive() {
        let status = EntitlementResolver.resolve(transactions: [transaction(monthlyID, expires: 9_000_000), transaction(annualID)], now: now)
        #expect(status.grant?.role == .annual)
    }

    @Test func productIDsAreTheConfiguredOnes() {
        #expect(PremiumProductRole.productIDs == ["relive.premium.annual", "relive.premium.monthly"])
        #expect(PremiumProductRole(productID: "relive.premium.monthly") == .monthly)
    }
}

@Suite("Premium: paywall words")
struct PaywallTextTests {
    private let year = SubscriptionPeriod(value: 1, unit: .year)
    private let week = SubscriptionPeriod(value: 1, unit: .week)

    @Test func startFreeTrialOnlyForARealEligibleTrial() {
        let trial = IntroductoryOffer(paymentMode: .freeTrial, period: week, displayPrice: "$0.00")
        var annual = PremiumProduct(id: annualID, role: .annual, displayName: "Relive Premium Annual", displayPrice: "$39.99", period: year, introductoryOffer: trial, isEligibleForIntroOffer: true)
        #expect(PaywallText.callToAction(annual) == "Start Free Trial")
        #expect(PaywallText.offerBadge(annual) == "1 week free")
        #expect(PaywallText.disclosure(annual).hasPrefix("Annual subscription: Free for 1 week, then $39.99 per year."))

        // Configured but not eligible (already used): no trial language at all.
        annual.isEligibleForIntroOffer = false
        #expect(PaywallText.callToAction(annual) == "Continue with Annual")
        #expect(PaywallText.offerBadge(annual) == nil)
        #expect(!PaywallText.disclosure(annual).localizedCaseInsensitiveContains("free"))

        // Not configured.
        annual.introductoryOffer = nil
        annual.isEligibleForIntroOffer = true
        #expect(PaywallText.callToAction(annual) == "Continue with Annual")
        #expect(PaywallText.disclosure(annual) == "Annual subscription: $39.99 per year. Renews automatically until cancelled. Cancel anytime in Settings at least 24 hours before the end of the current period.")
    }

    @Test func monthlyAndPricesComeFromTheStore() {
        let monthly = PremiumProduct(id: monthlyID, role: .monthly, displayName: "Relive Premium Monthly", displayPrice: "4,99 €", period: SubscriptionPeriod(value: 1, unit: .month))
        #expect(PaywallText.callToAction(monthly) == "Continue with Monthly")
        #expect(PaywallText.priceLine(monthly) == "4,99 € / month")
        #expect(PaywallText.callToAction(nil) == "Continue")
    }

    @Test func entryPointChangesOnlyTheContextLine() {
        let book = PaywallCopy(entry: .memoryBook)
        let year = PaywallCopy(entry: .ourYear)
        let collage = PaywallCopy(entry: .collageExport)
        #expect(book.context == "Keep this book")
        #expect(year.context == "Relive your full year")
        #expect(collage.context == "Create without limits")
        #expect(PaywallCopy(entry: .settings).context == nil)
        #expect(book.title == "Keep making memories worth keeping")
        #expect(book.title == year.title && book.benefits == collage.benefits && book.message == year.message)
        #expect(PaywallEntryPoint.memoryBook.capability == .memoryBookExport)
    }
}
