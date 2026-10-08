import SwiftUI

/// Chooses between onboarding and the main app, and keeps photo availability fresh.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(StoryStore.self) private var store
    @Environment(PremiumStore.self) private var premium
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
            // Listens for transaction updates once, and re-checks entitlements on every return.
            premium.start()
            Task {
                await store.refreshAvailability()
                // Keep each memory's date and place in step with the photo library, and repair
                // what an earlier version stored. Not during onboarding: its own run builds the story.
                guard !app.isOnboarding else { return }
                await store.repairMetadata()
                #if DEBUG
                EmbeddedDateAudit.runOnce(assets: Array(store.assets.values))
                #endif
            }
        }
    }
}
