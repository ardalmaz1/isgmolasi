import SwiftUI

@main
struct ReliveApp: App {
    @UIApplicationDelegateAdaptor(ReliveAppDelegate.self) private var appDelegate
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
                .environment(environment.premium)
                .environment(environment.madeForYou)
                .environment(environment.partner)
                .environment(\.photoImageLoader, environment.imageLoader)
                .environment(\.analytics, environment.analytics)
        }
    }
}
