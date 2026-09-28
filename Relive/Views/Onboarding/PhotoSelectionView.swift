import PhotosUI
import SwiftUI

/// Explains why photos are needed, then hands over to Apple's selection UI.
struct PhotoSelectionView: View {
    @Environment(AppModel.self) private var app
    @Environment(StoryStore.self) private var store
    @Environment(\.analytics) private var analytics
    @State private var selection = PhotoSelectionModel()

    var body: some View {
        OnboardingScaffold(onBack: { app.advance(to: .startDate) }) {
            Text("Your photos tell the story.")
                .font(Typography.display)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Choose the memories you’d like Relive to organize.")
                .font(Typography.title3)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Trips, dinners, ordinary days — photos and videos of the two of you. Somewhere between 50 and 500 works best.")
                .font(Typography.callout)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Spacing.xs)

            PrivacyNote()
                .padding(.top, Spacing.m)

            statusView
                .padding(.top, Spacing.s)
        } footer: {
            footer
        }
        .photosPicker(
            isPresented: $selection.isPickerPresented,
            selection: $selection.pickerItems,
            maxSelectionCount: PhotoSelectionModel.pickerLimit,
            selectionBehavior: .ordered,
            matching: .any(of: [.images, .videos]),
            preferredItemEncoding: .current,
            photoLibrary: .shared()
        )
        .onChange(of: selection.pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await selection.handlePickedItems(store: store, analytics: analytics) }
        }
        .onChange(of: selection.phase) { _, phase in
            if case .finished = phase, store.selectionCount >= PhotoSelectionModel.recommendedMinimum {
                app.advance(to: .processing)
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch selection.phase {
        case .importing, .requestingAccess:
            HStack(spacing: Spacing.s) {
                ProgressView()
                Text("Gathering your photos…")
                    .font(Typography.callout)
                    .foregroundStyle(Palette.textSecondary)
            }
        case .denied:
            AccessBanner(
                message: "Relive can’t see any photos right now. You can choose which ones it may see in Settings.",
                actionTitle: "Open Settings",
                action: SystemPresenter.openSettings
            )
        case .finished where store.selectionCount < PhotoSelectionModel.recommendedMinimum:
            Text(fewPhotosMessage)
                .font(Typography.callout)
                .foregroundStyle(Palette.textPrimary)
                .padding(Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var footer: some View {
        if case .finished = selection.phase, store.selectionCount > 0, store.selectionCount < PhotoSelectionModel.recommendedMinimum {
            Button("Continue with \(Counted.text(store.selectionCount, "memory", "memories"))") {
                app.advance(to: .processing)
            }
            .buttonStyle(.relivePrimary)
            Button("Add more photos", action: choose)
                .buttonStyle(.reliveQuiet)
        } else {
            Button("Choose Our Photos", action: choose)
                .buttonStyle(.relivePrimary)
                .disabled(selection.phase == .importing || selection.phase == .requestingAccess)
        }
    }

    private var fewPhotosMessage: String {
        if store.selectionCount == 0 {
            return "No photos chosen yet. Pick a few that feel like the two of you."
        }
        return "You chose \(Counted.text(store.selectionCount, "memory", "memories")). Relive finds more moments with 50 or more, but you can continue with these."
    }

    private func choose() {
        Task { await selection.choosePhotos(store: store, analytics: analytics) }
    }
}

/// "You control what Relive can see."
struct PrivacyNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: "lock")
                .font(.body)
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("You control what Relive can see.")
                    .font(Typography.callout.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text("Only the photos you choose. They stay on this iPhone and are organized on-device — nothing is uploaded, and there’s no account.")
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
