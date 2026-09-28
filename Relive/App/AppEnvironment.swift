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
        self.appModel = AppModel(storyStore: storyStore, repository: repository, analytics: analytics)
    }

    static func live() -> AppEnvironment {
        AppEnvironment(
            container: SwiftDataStoryRepository.makeContainer(),
            photoLibrary: PhotoKitLibraryService(),
            imageLoader: .shared,
            analytics: LoggingAnalyticsTracker()
        )
    }
}
