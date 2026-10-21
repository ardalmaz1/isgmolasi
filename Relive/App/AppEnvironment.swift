import Foundation
import ReliveCore
import SwiftData
import UIKit

/// Builds the object graph once at launch. Everything is injected, so a test or preview can
/// assemble the same models with fakes.
@MainActor
final class AppEnvironment {
    let container: ModelContainer
    let appModel: AppModel
    let storyStore: StoryStore
    let trendCatalog: TrendCatalogStore
    let imageLoader: PhotoImageLoader
    let analytics: any AnalyticsTracking
    let premium: PremiumStore
    let madeForYou: MadeForYouStore
    let partner: PartnerConnectionModel

    init(
        container: ModelContainer,
        photoLibrary: any PhotoLibraryProviding,
        imageLoader: PhotoImageLoader,
        analytics: any AnalyticsTracking,
        storeKit: any StoreKitClient = LiveStoreKitClient(),
        partner: PartnerConnectionModel? = nil
    ) {
        self.container = container
        self.imageLoader = imageLoader
        self.analytics = analytics
        let repository = SwiftDataStoryRepository(container: container)
        let storyStore = StoryStore(
            repository: repository,
            photoLibrary: photoLibrary,
            analyzer: VisionAssetAnalyzer(imageLoader: imageLoader),
            placeResolver: GeocodingPlaceResolver(),
            analytics: analytics
        )
        self.storyStore = storyStore
        self.trendCatalog = TrendCatalogStore()
        self.appModel = AppModel(storyStore: storyStore, repository: repository, analytics: analytics)
        self.premium = PremiumStore(client: storeKit, analytics: analytics)
        self.madeForYou = MadeForYouStore()
        self.partner = partner ?? PartnerConnectionModel(cache: InMemoryPartnerConnectionCache(), analytics: analytics) { CloudKitPartnerService() }
        PartnerInbox.shared.attach(self.partner)
        EditorialService.connect(analytics: analytics)
    }

    #if DEBUG
    /// UI tests pass this to start from onboarding regardless of earlier runs.
    static let startFreshArgument = "-ReliveUITestStartFresh"

    /// UI tests: `-ReliveStoreKit free|premium|trial|unavailable` replaces the App Store with
    /// `FakeStoreKitClient`, so no test depends on a live purchase. Without it, Debug builds use
    /// StoreKit (and `StoreKit/Relive.storekit` when run from Xcode).
    static func storeKitForUITests() -> (any StoreKitClient)? {
        guard let mode = UserDefaults.standard.string(forKey: "ReliveStoreKit") else { return nil }
        let fake = FakeStoreKitClient(products: FakeStoreKitClient.sampleProducts(withTrial: mode == "trial"))
        switch mode {
        case "premium":
            fake.snapshot.transactions = [fake.activeTransaction(.annual)]
        case "unavailable":
            fake.productFailure = .network
            fake.syncFailure = .network
        default:
            break
        }
        return fake
    }
    #endif

    static func live() -> AppEnvironment {
        let container = SwiftDataStoryRepository.makeContainer()
        #if DEBUG
        IntelligenceLog.install()
        if ProcessInfo.processInfo.arguments.contains(startFreshArgument) {
            SwiftDataStoryRepository(container: container).eraseEverything()
            PremiumStore.eraseLocalState()
            MadeForYouStore.eraseLocalState()
            FilePartnerConnectionCache().save(nil)
        }
        let storeKit: any StoreKitClient = storeKitForUITests() ?? LiveStoreKitClient()
        #else
        let storeKit: any StoreKitClient = LiveStoreKitClient()
        #endif
        EditorialService.shared.logProvider()
        let analytics = LoggingAnalyticsTracker()
        #if DEBUG
        let partner = partnerForUITests(analytics: analytics) ?? livePartner(analytics: analytics)
        #else
        let partner = livePartner(analytics: analytics)
        #endif
        return AppEnvironment(
            container: container,
            photoLibrary: PhotoKitLibraryService(),
            imageLoader: .shared,
            analytics: analytics,
            storeKit: storeKit,
            partner: partner
        )
    }

    /// The real partner connection: remembered in a small file, iCloud only on first use.
    private static func livePartner(analytics: any AnalyticsTracking) -> PartnerConnectionModel {
        PartnerConnectionModel(
            cache: FilePartnerConnectionCache(),
            analytics: analytics,
            // Silent updates only; registering needs no permission and shows nothing.
            onRelationship: { UIApplication.shared.registerForRemoteNotifications() },
            makeService: { CloudKitPartnerService() }
        )
    }
}
