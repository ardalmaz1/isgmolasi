import ReliveCore
import SwiftUI

/// Collages and stories still being made, most recently edited first. Relive keeps them
/// automatically; finishing one moves it to My Creations.
struct DraftsView: View {
    @Environment(StoryStore.self) private var store

    var body: some View {
        let drafts = store.drafts
        List {
            if drafts.isEmpty {
                QuietMessageView(title: "No drafts", message: "Collages and stories you’re still making will wait here.")
                    .listRowBackground(Color.clear)
            } else {
                ForEach(drafts) { draft in
                    DraftRow(draft: draft)
                        .listRowBackground(Palette.surface)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .reliveBackground()
        .navigationTitle("Drafts")
        .navigationBarTitleDisplayMode(.large)
    }
}

/// One draft: its picture, "Story · Edited 12 minutes ago", Continue and Delete.
struct DraftRow: View {
    let draft: SavedCreation

    @Environment(AppModel.self) private var app
    @Environment(StoryStore.self) private var store
    @State private var confirmsDelete = false

    var body: some View {
        let summary = KeptSummary(item: .creation(draft), store: store)
        HStack(spacing: Spacing.m) {
            Palette.background
                .frame(width: 72, height: 90)
                .overlay { CreationPreview(item: .creation(draft)).padding(4) }
                .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(summary.title)
                    .font(Typography.callout.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text("\(summary.kind.name) · \(EditedText.edited(draft.updatedAt))")
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.textSecondary)
                if summary.missingCount > 0 {
                    Text(Counted.text(summary.missingCount, "photo is missing", "photos are missing"))
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { app.resumeCreation(draft, origin: "drafts") }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Draft \(summary.kind.name.lowercased()), \(summary.title), \(EditedText.edited(draft.updatedAt))")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Continues editing")
        .accessibilityAction { app.resumeCreation(draft, origin: "drafts") }
        .accessibilityAction(named: "Delete Draft") { confirmsDelete = true }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { confirmsDelete = true } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button { app.resumeCreation(draft, origin: "drafts") } label: { Label("Continue Editing", systemImage: "pencil") }
            Button(role: .destructive) { confirmsDelete = true } label: { Label("Delete Draft", systemImage: "trash") }
        }
        .confirmationDialog("Delete this draft?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete Draft", role: .destructive) { store.deleteCreation(id: draft.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its photos stay in Relive and in the Photos app.")
        }
        .accessibilityIdentifier("draftRow")
    }
}
