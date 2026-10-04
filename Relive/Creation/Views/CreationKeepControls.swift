import ReliveCore
import SwiftUI

/// The editor's keep control: "Save" while the collage or story is a draft (or not kept yet);
/// once it is in My Creations, the heart that favorites it.
struct CreationKeepButton: View {
    let keeper: CreationKeeper
    let onSave: @MainActor () -> Void

    @State private var savedCount = 0

    var body: some View {
        if keeper.isSaved {
            FavoriteButton(
                kind: .creation,
                identifier: keeper.id.uuidString,
                label: keeper.kind == .collage ? "Favorite collage" : "Favorite story",
                accessibilityID: "creationFavorite"
            )
        } else {
            Button {
                onSave()
                savedCount += 1
                AccessibilityNotification.Announcement("Saved to My Creations").post()
            } label: {
                Text("Save")
                    .font(Typography.callout.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .sensoryFeedback(.success, trigger: savedCount)
            .accessibilityHint("Keeps it in My Creations")
            .accessibilityIdentifier("creationKeep")
        }
    }
}

/// "…" in the editor: deleting a kept draft or creation (with confirmation). Shown once there
/// is something to delete.
struct CreationMoreMenu: View {
    let keeper: CreationKeeper
    let onDelete: @MainActor () -> Void

    var body: some View {
        if keeper.exists {
            Menu {
                Button(role: .destructive, action: onDelete) {
                    Label(keeper.isSaved ? "Delete \(noun)" : "Delete Draft", systemImage: "trash")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("creationMore")
        }
    }

    private var noun: String { keeper.kind == .collage ? "Collage" : "Story" }
}

extension View {
    /// Asks before deleting a kept draft or creation, then deletes it and closes the editor.
    /// The photos it used stay, in Relive and in the Photos app.
    func confirmsCreationDelete(isPresented: Binding<Bool>, keeper: CreationKeeper, store: StoryStore, onDeleted: @escaping @MainActor () -> Void) -> some View {
        let noun = keeper.kind == .collage ? "collage" : "story"
        let title = keeper.isSaved ? "Delete this \(noun)?" : "Delete this draft?"
        return confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible) {
            Button(keeper.isSaved ? "Delete \(noun.capitalized)" : "Delete Draft", role: .destructive) {
                let id = keeper.id
                keeper.forget()
                store.deleteCreation(id: id)
                onDeleted()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its photos stay in Relive and in the Photos app.")
        }
    }
}
