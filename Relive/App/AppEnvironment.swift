import Foundation
import ReliveCore
import SwiftData

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

    init(
        container: ModelContainer,
        photoLibrary: any PhotoLibraryProviding,
        imageLoader: PhotoImageLoader,
        analytics: any AnalyticsTracking
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
    }

    #if DEBUG
    /// UI tests pass this to start from onboarding regardless of earlier runs.
    static let startFreshArgument = "-ReliveUITestStartFresh"
    #endif

    static func live() -> AppEnvironment {
        let container = SwiftDataStoryRepository.makeContainer()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(startFreshArgument) {
            SwiftDataStoryRepository(container: container).deleteAll()
        }
        #endif
        return AppEnvironment(
            container: container,
            photoLibrary: PhotoKitLibraryService(),
            imageLoader: .shared,
            analytics: LoggingAnalyticsTracker()
        )
    }
}
