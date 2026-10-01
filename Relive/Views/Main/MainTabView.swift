import ReliveCore
import SwiftUI

/// Four tabs: Today, Story, Create, Us. Collages and stories open over everything, from
/// whichever screen asked for them.
struct MainTabView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selectedTab) {
            Tab("Today", systemImage: "sun.max", value: AppModel.Tab.today) {
                TodayView()
            }
            Tab("Story", systemImage: "book.closed", value: AppModel.Tab.story) {
                StoryTimelineView()
            }
            Tab("Create", systemImage: "photo.on.rectangle.angled", value: AppModel.Tab.create) {
                CreateHomeView()
            }
            Tab("Us", systemImage: "person.2", value: AppModel.Tab.us) {
                UsView()
            }
        }
        .fullScreenCover(item: $app.activeCreation) { request in
            CreationFlowView(request: request)
        }
    }
}

/// Navigation value for opening a moment. `source` feeds analytics ("timeline", "today"…).
struct MomentRoute: Hashable {
    let momentID: MomentID
    let source: String
}

extension View {
    /// Registers the moment detail destination for a navigation stack.
    func momentDestination() -> some View {
        navigationDestination(for: MomentRoute.self) { route in
            MomentDetailView(momentID: route.momentID, source: route.source)
        }
    }
}
