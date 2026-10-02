import SwiftUI

@main
struct ReliveApp: App {
    @State private var environment: AppEnvironment

    init() {
        _environment = State(initialValue: AppEnvironment.live())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment.appModel)
                .environment(environment.storyStore)
                .environment(environment.trendCatalog)
                .environment(\.photoImageLoader, environment.imageLoader)
                .environment(\.analytics, environment.analytics)
        }
    }
}
