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
    case memoryMovie = "memory_movie"
    /// The hard paywall after onboarding, once the story has been revealed.
    case welcome
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
        case .memoryMovie: .memoryMovie
        case .welcome, .settings: nil
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
        let w = CoreWords()
        context = switch entry {
        case .memoryBook: w.pick("Keep this book", "Bu kitabı saklayın")
        case .ourYear: w.pick("See your full year", "Yılınızın tamamını görün")
        case .monthlyRecap: w.pick("See the whole month", "Ayın tamamını görün")
        case .collageExport, .trendExport: w.pick("Create without limits", "Sınırsız oluşturun")
        case .storyExport: w.pick("Keep every story", "Her hikâyeyi saklayın")
        case .premiumStyle: w.pick("Every design", "Tüm tasarımlar")
        case .memoryMovie: w.pick("Keep this movie", "Bu filmi saklayın")
        case .welcome: w.pick("Your story is ready", "Hikâyeniz hazır")
        case .settings: nil
        }
        if entry == .welcome {
            title = w.pick("Keep your story, together", "Hikâyenizi birlikte saklayın")
            message = w.pick("Yuvi Premium opens everything Yuvi made from your photos. One subscription covers you both.", "Yuvi Premium, Yuvi'nin fotoğraflarınızdan hazırladığı her şeyi açar. Tek abonelik ikinizi de kapsar.")
            benefits = [
                w.pick("Your whole story: moments, trips and places", "Hikâyenizin tamamı: anlar, geziler ve yerler"),
                w.pick("Today, Monthly Recap and Our Year", "Bugün, Aylık Özet ve Bizim Yılımız"),
                w.pick("Memory Movies, Books, Collages & Stories", "Anı Filmleri, Kitaplar, Kolajlar ve Hikâyeler"),
                w.pick("Your partner joins free with your invitation", "Partneriniz davetinizle ücretsiz katılır"),
                w.pick("Private: your photos never leave your iPhone", "Gizli: fotoğraflarınız iPhone'unuzdan hiç çıkmaz"),
            ]
            return
        }
        title = w.pick("Keep making memories worth keeping", "Saklamaya değer anılar biriktirmeye devam edin")
        message = w.pick("Your memories are always yours.\nPremium gives you everything Yuvi can create from them.", "Anılarınız her zaman sizin.\nPremium, Yuvi'nin onlardan oluşturabileceği her şeyi açar.")
        benefits = [
            w.pick("Unlimited Memory Books", "Sınırsız Anı Kitabı"),
            w.pick("Stories, Collages & Memory Movies", "Hikâyeler, Kolajlar ve Anı Filmleri"),
            w.pick("Monthly and yearly recaps", "Aylık ve yıllık özetler"),
            w.pick("Every premium design", "Tüm premium tasarımlar"),
            w.pick("Full-quality exports", "Tam kaliteli dışa aktarım"),
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
        if CoreWords().isTurkish { return value == 1 ? turkishUnit : "\(value) \(turkishUnit)" }
        return value == 1 ? unit.rawValue : "\(value) \(unit.rawValue)s"
    }

    /// "1 week", "3 days", "1 month".
    public var durationPhrase: String {
        if CoreWords().isTurkish { return "\(value) \(turkishUnit)" }
        return "\(value) \(value == 1 ? unit.rawValue : unit.rawValue + "s")"
    }

    private var turkishUnit: String {
        switch unit.rawValue {
        case "day": "gün"
        case "week": "hafta"
        case "month": "ay"
        default: "yıl"
        }
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
        case .annual: CoreWords().pick("Annual", "Yıllık")
        case .monthly: CoreWords().pick("Monthly", "Aylık")
        }
    }

    /// "€39.99 / year".
    public static func priceLine(_ product: PremiumProduct) -> String {
        "\(product.displayPrice) / \(product.period.recurringPhrase)"
    }

    /// "1 week free" — only for a trial the App Store says the user can start.
    public static func offerBadge(_ product: PremiumProduct) -> String? {
        guard let offer = product.availableOffer else { return nil }
        if CoreWords().isTurkish {
            return switch offer.paymentMode {
            case .freeTrial: "\(totalDuration(offer)) ücretsiz"
            case .payAsYouGo: "Başlangıçta \(offer.displayPrice) / \(offer.period.recurringPhrase)"
            case .payUpFront: "İlk \(totalDuration(offer)) \(offer.displayPrice)"
            }
        }
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
        let w = CoreWords()
        guard let product else { return w.pick("Continue", "Devam Et") }
        if product.freeTrial != nil { return w.pick("Start Free Trial", "Ücretsiz Denemeyi Başlat") }
        return w.pick("Continue with \(planName(product.role))", "\(planName(product.role)) ile Devam Et")
    }

    /// The recurring-subscription disclosure under the button.
    public static func disclosure(_ product: PremiumProduct) -> String {
        if CoreWords().isTurkish { return turkishDisclosure(product) }
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

    private static func turkishDisclosure(_ product: PremiumProduct) -> String {
        let renews = "İptal edilene kadar otomatik yenilenir. Dönem bitmeden en az 24 saat önce Ayarlar'dan istediğiniz zaman iptal edebilirsiniz."
        let recurring = "\(product.period.recurringPhrase) başına \(product.displayPrice)"
        guard let offer = product.availableOffer else {
            return "\(planName(product.role)) abonelik: \(recurring). \(renews)"
        }
        let start = switch offer.paymentMode {
        case .freeTrial: "\(totalDuration(offer)) ücretsiz"
        case .payAsYouGo: "\(totalDuration(offer)) boyunca \(offer.period.recurringPhrase) başına \(offer.displayPrice)"
        case .payUpFront: "\(totalDuration(offer)) için \(offer.displayPrice)"
        }
        return "\(planName(product.role)) abonelik: \(start), ardından \(recurring). \(renews)"
    }

    private static func totalDuration(_ offer: IntroductoryOffer) -> String {
        SubscriptionPeriod(value: offer.period.value * max(1, offer.periodCount), unit: offer.period.unit).durationPhrase
    }
}
