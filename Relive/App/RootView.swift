import SwiftUI

/// Chooses between onboarding and the main app, and keeps photo availability fresh.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(StoryStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if app.isOnboarding {
                OnboardingFlowView()
                    .transition(.opacity)
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: app.isOnboarding)
        .tint(Palette.accent)
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            Task { await store.refreshAvailability() }
        }
    }
}
