import SwiftUI

/// Chooses between onboarding and the main app, and keeps photo availability fresh.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(StoryStore.self) private var store
    @Environment(PremiumStore.self) private var premium
    @Environment(PartnerConnectionModel.self) private var partner
    @Environment(\.scenePhase) private var scenePhase

    /// UI tests that exercise the in-app Premium gates turn the wall off
    /// (`-ReliveUITestNoHardPaywall`).
    static var hardPaywall: Bool {
        #if DEBUG
        !ProcessInfo.processInfo.arguments.contains("-ReliveUITestNoHardPaywall")
        #else
        true
        #endif
    }

    var body: some View {
        ZStack {
            if app.isOnboarding {
                OnboardingFlowView()
                    .transition(.opacity)
            } else if premium.hasAppAccess || !Self.hardPaywall {
                MainTabView()
                    .transition(.opacity)
            } else {
                // The hard paywall: the story is built and revealed, Premium opens it.
                PaywallView(entry: .welcome) {}
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: app.isOnboarding)
        .animation(.easeInOut(duration: 0.45), value: premium.hasAppAccess)
        .onChange(of: partner.record, initial: true) { _, record in
            // An invited partner is covered by the inviting partner's subscription.
            premium.isCoveredByPartner = record?.role == .partner && record?.status == .connected
        }
        .tint(Palette.accent)
        #if DEBUG
        // Screenshot review in dark mode (UI tests: -ReliveUITestDarkMode).
        .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("-ReliveUITestDarkMode") ? .dark : nil)
        #endif
        .partnerNotice()
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            // Listens for transaction updates once, and re-checks entitlements on every return.
            premium.start()
            // Only when a partner is connected (or invited): solo Relive never asks iCloud.
            Task { await partner.refresh() }
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
