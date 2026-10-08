import Foundation

/// Why the paywall opened. Changes one line of copy, never the paywall itself.
public enum PaywallEntryPoint: String, CaseIterable, Codable, Sendable {
    case collageExport = "collage_export"
    case storyExport = "story_export"
    case trendExport = "trend_export"
    case memoryBook = "memory_book"
    case monthlyRecap = "monthly_recap"
    case ourYear = "our_year"
    case premiumStyle = "premium_style"
    case settings

    /// The capability the user was reaching for (for analytics and for the unlock check).
    public var capability: PremiumCapability? {
        switch self {
        case .collageExport: .collageExport
        case .storyExport: .storyExport
        case .trendExport: .trendExport
        case .memoryBook: .memoryBookExport
        case .monthlyRecap: .fullMonthlyRecap
        case .ourYear: .fullYearInReview
        case .premiumStyle: .premiumStyles
        case .settings: nil
        }
    }
}

/// The paywall's words. One paywall; the entry point only sets the small line above the title.
public struct PaywallCopy: Equatable, Sendable {
    public var context: String?
    public var title: String
    public var message: String
    public var benefits: [String]

    public init(entry: PaywallEntryPoint) {
        context = switch entry {
        case .memoryBook: "Keep this book"
        case .ourYear: "Relive your full year"
        case .monthlyRecap: "See the whole month"
        case .collageExport, .trendExport: "Create without limits"
        case .storyExport: "Keep every story"
        case .premiumStyle: "Every design"
        case .settings: nil
        }
        title = "Keep making memories worth keeping"
        message = "Your memories are always yours.\nPremium gives you everything Relive can create from them."
        benefits = [
            "Unlimited Memory Books",
            "Stories, Collages & future Movies",
            "Monthly and yearly recaps",
            "Every premium design",
            "Full-quality exports",
        ]
    }
}

/// A subscription length, as the App Store reports it.
public struct SubscriptionPeriod: Equatable, Sendable {
    public enum Unit: String, Sendable {
        case day, week, month, year
    }

    public var value: Int
    public var unit: Unit

    public init(value: Int, unit: Unit) {
        self.value = value
        self.unit = unit
    }

    /// "year", "month", "3 months".
    public var recurringPhrase: String {
        value == 1 ? unit.rawValue : "\(value) \(unit.rawValue)s"
    }

    /// "1 week", "3 days", "1 month".
    public var durationPhrase: String {
        "\(value) \(value == 1 ? unit.rawValue : unit.rawValue + "s")"
    }
}

/// An introductory offer configured in App Store Connect.
public struct IntroductoryOffer: Equatable, Sendable {
    public enum PaymentMode: String, Sendable {
        case freeTrial, payAsYouGo, payUpFront
    }

    public var paymentMode: PaymentMode
    /// The length of one offer period.
    public var period: SubscriptionPeriod
    public var periodCount: Int
    /// Localized, from the App Store.
    public var displayPrice: String

    public init(paymentMode: PaymentMode, period: SubscriptionPeriod, periodCount: Int = 1, displayPrice: String) {
        self.paymentMode = paymentMode
        self.period = period
        self.periodCount = periodCount
        self.displayPrice = displayPrice
    }
}

/// A Premium product as the paywall shows it. Every price and name is the App Store's own
/// localized value; nothing here is invented.
public struct PremiumProduct: Equatable, Identifiable, Sendable {
    public var id: String
    public var role: PremiumProductRole
    public var displayName: String
    public var displayPrice: String
    public var period: SubscriptionPeriod
    public var introductoryOffer: IntroductoryOffer?
    /// StoreKit's own answer; never assumed.
    public var isEligibleForIntroOffer: Bool

    public init(id: String, role: PremiumProductRole, displayName: String, displayPrice: String, period: SubscriptionPeriod, introductoryOffer: IntroductoryOffer? = nil, isEligibleForIntroOffer: Bool = false) {
        self.id = id
        self.role = role
        self.displayName = displayName
        self.displayPrice = displayPrice
        self.period = period
        self.introductoryOffer = introductoryOffer
        self.isEligibleForIntroOffer = isEligibleForIntroOffer
    }

    /// The offer the user would actually get, if any.
    public var availableOffer: IntroductoryOffer? {
        isEligibleForIntroOffer ? introductoryOffer : nil
    }

    /// A free trial the App Store says this user can start.
    public var freeTrial: IntroductoryOffer? {
        availableOffer.flatMap { $0.paymentMode == .freeTrial ? $0 : nil }
    }
}

/// Plan rows, the button and the subscription disclosure.
public enum PaywallText {
    public static func planName(_ role: PremiumProductRole) -> String {
        switch role {
        case .annual: "Annual"
        case .monthly: "Monthly"
        }
    }

    /// "€39.99 / year".
    public static func priceLine(_ product: PremiumProduct) -> String {
        "\(product.displayPrice) / \(product.period.recurringPhrase)"
    }

    /// "1 week free" — only for a trial the App Store says the user can start.
    public static func offerBadge(_ product: PremiumProduct) -> String? {
        guard let offer = product.availableOffer else { return nil }
        switch offer.paymentMode {
        case .freeTrial:
            return "\(totalDuration(offer)) free"
        case .payAsYouGo:
            return "\(offer.displayPrice) / \(offer.period.recurringPhrase) to start"
        case .payUpFront:
            return "\(offer.displayPrice) for the first \(totalDuration(offer))"
        }
    }

    /// "Start Free Trial" only when there is a real trial to start; otherwise honest words.
    public static func callToAction(_ product: PremiumProduct?) -> String {
        guard let product else { return "Continue" }
        if product.freeTrial != nil { return "Start Free Trial" }
        return "Continue with \(planName(product.role))"
    }

    /// The recurring-subscription disclosure under the button.
    public static func disclosure(_ product: PremiumProduct) -> String {
        let renews = "Renews automatically until cancelled. Cancel anytime in Settings at least 24 hours before the end of the current period."
        let recurring = "\(product.displayPrice) per \(product.period.recurringPhrase)"
        guard let offer = product.availableOffer else {
            return "\(planName(product.role)) subscription: \(recurring). \(renews)"
        }
        let start = switch offer.paymentMode {
        case .freeTrial: "Free for \(totalDuration(offer))"
        case .payAsYouGo: "\(offer.displayPrice) per \(offer.period.recurringPhrase) for \(totalDuration(offer))"
        case .payUpFront: "\(offer.displayPrice) for \(totalDuration(offer))"
        }
        return "\(planName(product.role)) subscription: \(start), then \(recurring). \(renews)"
    }

    private static func totalDuration(_ offer: IntroductoryOffer) -> String {
        SubscriptionPeriod(value: offer.period.value * max(1, offer.periodCount), unit: offer.period.unit).durationPhrase
    }
}
