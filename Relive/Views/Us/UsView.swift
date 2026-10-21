import ReliveCore
import SwiftUI

/// The two of you, a few honest numbers, and settings.
struct UsView: View {
    @Environment(AppModel.self) private var app
    @Environment(StoryStore.self) private var store
    @Environment(PremiumStore.self) private var premium
    @State private var isEditingProfile = false
    @State private var isAddingMemories = false
    @State private var confirmsStartOver = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    UsHeader()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                // The archive: every memory, moment and place — always free to browse.
                Section {
                    NavigationLink(value: ArchiveRoute.memories) {
                        StatRow(title: "Memories", value: store.statistics.memoryCount)
                    }
                    .accessibilityIdentifier("usMemories")
                    NavigationLink(value: ArchiveRoute.moments) {
                        StatRow(title: "Moments", value: store.statistics.momentCount)
                    }
                    .accessibilityIdentifier("usMoments")
                    NavigationLink(value: ArchiveRoute.places) {
                        StatRow(title: "Places", value: store.statistics.placeCount)
                    }
                    .accessibilityIdentifier("usPlaces")
                }
                .listRowBackground(Palette.surface)

                Section("Kept in Relive") {
                    NavigationLink(value: CollectionRoute.favorites) {
                        CountRow(title: "Favorites", count: store.visibleFavoritesCount)
                    }
                    .accessibilityIdentifier("usFavorites")
                    NavigationLink(value: CollectionRoute.creations) {
                        CountRow(title: "My Creations", count: store.keptItems.count)
                    }
                    .accessibilityIdentifier("usCreations")
                    if !store.drafts.isEmpty {
                        NavigationLink(value: CollectionRoute.drafts) {
                            CountRow(title: "Drafts", count: store.drafts.count)
                        }
                    }
                }
                .listRowBackground(Palette.surface)

                Section("Relive Premium") {
                    NavigationLink {
                        PremiumSettingsView()
                    } label: {
                        LabeledContent("Premium") {
                            Text(premium.showsPremium ? "Active" : "Free")
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .accessibilityIdentifier("usPremium")
                    Button("Restore Purchases") { Task { await premium.restore(entry: .settings) } }
                        .disabled(premium.restoreState == .restoring)
                        .accessibilityIdentifier("usRestore")
                    RestoreStatusText()
                }
                .listRowBackground(Palette.surface)

                Section("Your story") {
                    Button("Edit Names and Date") { isEditingProfile = true }
                    NavigationLink("Hidden Memories") { HiddenMemoriesView() }
                    Button("Add Memories") { isAddingMemories = true }
                }
                .listRowBackground(Palette.surface)

                Section {
                    PhotoAccessRow()
                } header: {
                    Text("Photo access")
                } footer: {
                    Text("Your story holds only the photos you chose or kept. Relive never identifies people. You can change access any time in Settings.")
                }
                .listRowBackground(Palette.surface)

                Section("Privacy") {
                    Text("Your photos are organized on this iPhone and aren’t uploaded; there is no account and no feed. When Relive suggests moments, it reads dates and places and counts faces in a few photos — it never knows who anyone is. To name places, Relive asks Apple’s location service about a location — never a photo. Photos kept only in iCloud may be downloaded from your own iCloud to show them.")
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.vertical, Spacing.xxs)
                }
                .listRowBackground(Palette.surface)

                Section {
                    Button("Start Over", role: .destructive) { confirmsStartOver = true }
                } footer: {
                    Text("Relive \(Self.versionText)")
                        .frame(maxWidth: .infinity)
                        .padding(.top, Spacing.l)
                }
                .listRowBackground(Palette.surface)
            }
            .scrollContentBackground(.hidden)
            .reliveBackground()
            .statusBarBackdrop()
            .foregroundStyle(Palette.textPrimary)
            .toolbar(.hidden, for: .navigationBar)
            .momentDestination()
            .collectionDestinations()
            .archiveDestinations()
            .sheet(isPresented: $isEditingProfile) { EditProfileView() }
            .confirmationDialog(
                "Start over?",
                isPresented: $confirmsStartOver,
                titleVisibility: .visible
            ) {
                Button("Delete Relive’s Data", role: .destructive) { app.startOver() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes your story, notes and settings from Relive, and you’ll set it up again. Your books, collages, stories, movies, drafts and favorites stay, and so do memories you asked Relive not to suggest. Your photos in the Photos app are not touched.")
            }
        }
        .addMemoriesFlow(isPresented: $isAddingMemories)
    }

    private static var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
        return "Prototype \(version)"
    }
}

/// "You ♥ Emma · Together since March 2021 · 1,568 days"
private struct UsHeader: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Us")
                .eyebrowStyle()
            CoupleTitle()
                .font(Typography.display)
                .foregroundStyle(Palette.textPrimary)
            if let start = app.relationship?.start {
                Text("Together since \(DateText.relationshipStart(start))")
                    .font(Typography.callout)
                    .foregroundStyle(Palette.textSecondary)
                let days = start.daysTogether(until: Date(), calendar: .current)
                Text(start.isApproximate ? "About \(Counted.text(days, "day", "days"))" : Counted.text(days, "day", "days"))
                    .font(Typography.title2)
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.top, Spacing.xs)
            }
        }
        .padding(.top, Spacing.l)
        .padding(.bottom, Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// "Favorites   12" inside a navigation row.
private struct CountRow: View {
    let title: String
    let count: Int

    var body: some View {
        LabeledContent(title) {
            Text(count.formatted())
                .font(Typography.body.monospacedDigit())
                .foregroundStyle(Palette.textSecondary)
        }
    }
}

private struct StatRow: View {
    let title: String
    let value: Int

    var body: some View {
        LabeledContent(title) {
            Text(value.formatted())
                .font(Typography.body.monospacedDigit())
                .foregroundStyle(Palette.textPrimary)
                .accessibilityIdentifier("stat-\(title)")
        }
    }
}

/// Shows what Relive can see and how to change it.
private struct PhotoAccessRow: View {
    @Environment(StoryStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(statusText)
                .font(Typography.callout)
            Button(actionTitle) {
                if store.accessStatus == .limited {
                    Task {
                        _ = await SystemPresenter.presentLimitedLibraryPicker()
                        await store.refreshAvailability()
                    }
                } else {
                    SystemPresenter.openSettings()
                }
            }
            .font(Typography.callout.weight(.semibold))
        }
        .padding(.vertical, Spacing.xxs)
    }

    private var statusText: String {
        switch store.accessStatus {
        case .limited: "Relive sees only the \(Counted.text(store.selectionCount, "photo", "photos")) you chose."
        case .full: "Full access is on, so Relive can suggest moments when you ask it to. Your story holds the \(Counted.text(store.selectionCount, "photo", "photos")) you chose or kept."
        case .denied, .restricted: "Relive can’t see any photos right now."
        case .notDetermined: "Relive hasn’t asked to see any photos yet."
        }
    }

    private var actionTitle: String {
        store.accessStatus == .limited ? "Change Selection" : "Open Settings"
    }
}
