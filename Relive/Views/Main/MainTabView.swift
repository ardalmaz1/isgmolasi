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
        // One cover for both: a second cover chained on the same view doesn't reliably present.
        .fullScreenCover(item: cover, onDismiss: { app.recapDismissed() }) { cover in
            switch cover {
            case .creation(let request): CreationFlowView(request: request)
            case .recap(let request): RecapExperienceView(request: request)
            }
        }
    }

    /// What's open over everything: a creation, or the immersive recap.
    private enum Cover: Identifiable {
        case creation(CreationRequest)
        case recap(RecapRequest)

        var id: UUID {
            switch self {
            case .creation(let request): request.id
            case .recap(let request): request.id
            }
        }
    }

    private var cover: Binding<Cover?> {
        Binding(
            get: { app.activeCreation.map(Cover.creation) ?? app.activeRecap.map(Cover.recap) },
            set: { value in
                guard value == nil else { return }
                app.activeCreation = nil
                app.activeRecap = nil
            }
        )
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
