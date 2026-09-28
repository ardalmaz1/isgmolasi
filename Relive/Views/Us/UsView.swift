import ReliveCore
import SwiftUI

/// The two of you, a few honest numbers, and settings.
struct UsView: View {
    @Environment(AppModel.self) private var app
    @Environment(StoryStore.self) private var store
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

                Section {
                    StatRow(title: "Memories", value: store.statistics.memoryCount)
                    StatRow(title: "Moments", value: store.statistics.momentCount)
                    StatRow(title: "Places", value: store.statistics.placeCount)
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
                    Text("Relive only sees the photos you choose. You can change this any time.")
                }
                .listRowBackground(Palette.surface)

                Section("Privacy") {
                    Text("Your photos stay on this iPhone and are organized on-device. Nothing is uploaded and there is no account. To name places, Relive asks Apple’s location service about a location — never a photo.")
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
            .foregroundStyle(Palette.textPrimary)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isEditingProfile) { EditProfileView() }
            .confirmationDialog(
                "Start over?",
                isPresented: $confirmsStartOver,
                titleVisibility: .visible
            ) {
                Button("Delete Relive’s Data", role: .destructive) { app.startOver() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes your story, notes and settings from Relive. Your photos in the Photos app are not touched.")
            }
        }
        .addMemoriesFlow(isPresented: $isAddingMemories)
    }

    private static var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
        return "Prototype \(version)"
    }
}

/// "You + Emma · Together since March 2021 · 1,568 days"
private struct UsHeader: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Us")
                .eyebrowStyle()
            Text(app.coupleName)
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

private struct StatRow: View {
    let title: String
    let value: Int

    var body: some View {
        LabeledContent(title) {
            Text(value.formatted())
                .font(Typography.body.monospacedDigit())
                .foregroundStyle(Palette.textPrimary)
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
        case .full: "Relive keeps \(Counted.text(store.selectionCount, "photo", "photos")) you chose. Full library access is on, but only chosen photos are used."
        case .denied, .restricted: "Relive can’t see any photos right now."
        case .notDetermined: "Relive hasn’t asked to see any photos yet."
        }
    }

    private var actionTitle: String {
        store.accessStatus == .limited ? "Change Selection" : "Open Settings"
    }
}
