import ReliveCore
import SwiftUI

/// Three tabs, nothing more: Today, Story, Us.
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
            Tab("Us", systemImage: "person.2", value: AppModel.Tab.us) {
                UsView()
            }
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
